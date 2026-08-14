"""RouterBrainProvider — Valar's daily-model + on-demand-swap front door.

Valar owns persona->model routing (the body, not the brain). This provider wraps
the streaming data plane (RustBrainProvider, talking to llama-server's native
OpenAI SSE on :8080) with a control plane: a switch_persona call to the Rust
supervisor's WebSocket (:8765) that makes the right model resident before we
stream. It mirrors the proven Hermes daily+swap pattern, but inside Valar so the
voice clients and Telegram share ONE pipeline.

Routing is by model class (the persona's deep_model.path):
  - same class (e.g. valinor-daily <-> valinor-orchestrate, both gemma-4-E4B)
    -> no switch (Rust would no-op anyway; we skip the round-trip).
  - cross class (e.g. valinor-daily -> Sulivan 35B) -> exactly one switch_persona,
    waited on with pings disabled (Rust's WS blocks during the load).

decide_model() is the seam for future automatic (HRM-style) escalation. Today it
returns the persona-driven choice unchanged: explicit swap only.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import AsyncIterator

import websockets

from .prompt_dialect import PromptDialect, dialect_from_model
from .provider import BrainStreamResult, ChatMessage, ChatOptions
from .rust_provider import BrainError, RustBrainProvider

logger = logging.getLogger("valar.brain.router")


class RouterBrainProvider:
    """Persona-driven model router in front of the streaming Rust data plane."""

    name = "router"

    def __init__(
        self,
        base_url: str,
        switch_ws_url: str,
        request_timeout_s: int = 300,
        switch_timeout_s: int = 330,
        idle_persona: str = "valinor-daily",
        idle_swap_timeout_s: int = 300,
    ):
        # Data plane: stream tokens from the OpenAI-compatible endpoint (base_url
        # should point at llama-server :8080/v1 for native streaming).
        self._inner = RustBrainProvider(base_url, request_timeout_s)
        # Control plane: Rust supervisor WS for switch_persona.
        self._switch_ws_url = switch_ws_url.rstrip("/")
        self._switch_timeout_s = switch_timeout_s
        # The model class (deep_model.path) currently resident on the brain. Empty
        # until the first routed turn — the first turn for any class pays the swap
        # (a no-op if that class is already resident).
        self._loaded_model_path = ""
        self.prompt_dialect = PromptDialect.OPENAI
        # Serialize swaps so two concurrent turns can't switch the model out from
        # under each other.
        self._swap_lock = asyncio.Lock()

        # Idle-persona watchdog: after a heavy model sits idle, swap back to the
        # daily/idle persona's model to free VRAM. We learn the idle model path
        # lazily from the first idle-persona turn (no need to read persona JSON
        # here) so "heavy" == "loaded model != idle model".
        self._idle_persona = idle_persona
        self._idle_swap_timeout_s = idle_swap_timeout_s
        self._idle_model_path = ""           # learned from idle-persona turns
        self._last_activity = time.monotonic()
        self._watchdog_task: asyncio.Task | None = None

    async def chat(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        result: BrainStreamResult,
    ) -> AsyncIterator[str]:
        self._last_activity = time.monotonic()
        self._ensure_watchdog()
        await self._ensure_model(opts)
        # A turn just used the brain — refresh activity so a long generation
        # doesn't let the watchdog fire mid-conversation.
        self._last_activity = time.monotonic()
        async for delta in self._inner.chat(messages, opts, result):
            yield delta

    async def chat_tools(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        tools: list,
    ) -> dict:
        """Tool-aware round-trip with model routing applied first. Makes the
        persona's model resident (one switch_persona if needed), then delegates
        to the inner Rust provider. Refreshes activity so the idle watchdog does
        not fire between the tool call and the final streaming answer."""
        self._last_activity = time.monotonic()
        self._ensure_watchdog()
        await self._ensure_model(opts)
        try:
            return await self._inner.chat_tools(messages, opts, tools)
        finally:
            self._last_activity = time.monotonic()

    async def chat_structured(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        schema: dict,
        name: str = "structured_reply",
    ) -> str:
        """Grammar-constrained round-trip with model routing applied first. The
        interview runs on this; without the passthrough the voice loop sees no
        chat_structured on the router and silently falls back to the tool path
        (found live 2026-08-08)."""
        self._last_activity = time.monotonic()
        self._ensure_watchdog()
        await self._ensure_model(opts)
        try:
            return await self._inner.chat_structured(messages, opts, schema, name)
        finally:
            self._last_activity = time.monotonic()

    async def health(self) -> bool:
        return await self._inner.health()

    async def warm(self, opts: ChatOptions) -> None:
        """Startup warm-up: make the persona's model resident (one switch_persona
        if needed) without generating, so the first real turn skips the swap. Also
        starts the idle watchdog. Best-effort — caller logs and continues on error."""
        self._last_activity = time.monotonic()
        self._ensure_watchdog()
        await self._ensure_model(opts)

    # --- routing -------------------------------------------------------------

    def decide_model(
        self, persona_name: str, model_path: str, opts: ChatOptions
    ) -> tuple[str, str]:
        """Seam for future automatic escalation. Today: persona-driven, unchanged.

        A later phase can inspect `opts`/messages here and return a heavier
        (persona_name, model_path) to escalate. Keeping it pure + explicit keeps
        the default path predictable and low-latency.
        """
        return persona_name, model_path

    async def _ensure_model(self, opts: ChatOptions) -> None:
        persona_name, model_path = self.decide_model(
            (opts.persona_name or "").strip(),
            (opts.model_path or "").strip(),
            opts,
        )
        # Nothing to route on (e.g. a caller that didn't set persona/model) — just
        # stream against whatever is resident.
        if not persona_name or not model_path:
            if self._loaded_model_path:
                self._stamp_dialect(self._loaded_model_path, opts)
            return
        # Learn the idle (daily) model path from idle-persona turns so the watchdog
        # can distinguish "heavy" (loaded != idle) from "already on the daily model".
        if persona_name == self._idle_persona:
            self._idle_model_path = model_path
        async with self._swap_lock:
            if model_path == self._loaded_model_path:
                self._stamp_dialect(model_path, opts)
                return  # already resident (same model class) — no swap needed
            logger.info(
                "router: model class change (%s -> %s); switch_persona %s",
                self._loaded_model_path or "(none)",
                model_path,
                persona_name,
            )
            await self._switch_persona(persona_name)
            self._loaded_model_path = model_path
            self._stamp_dialect(model_path, opts)

    def _stamp_dialect(self, model_path: str, opts: ChatOptions) -> None:
        """Record the resident GGUF's prompt dialect on the router and this turn."""
        dialect = dialect_from_model(model_path)
        if dialect != self.prompt_dialect:
            logger.info("router: prompt dialect %s for %s", dialect.value, model_path)
        self.prompt_dialect = dialect
        opts.prompt_dialect = dialect

    # --- idle watchdog -------------------------------------------------------

    def _ensure_watchdog(self) -> None:
        """Lazily start the idle watchdog on the running event loop (first turn)."""
        if self._idle_swap_timeout_s <= 0:
            return
        if self._watchdog_task is None or self._watchdog_task.done():
            self._watchdog_task = asyncio.create_task(self._idle_watchdog())

    async def _idle_watchdog(self) -> None:
        """Swap the brain back to the idle (daily) model after inactivity on a
        heavier model, freeing VRAM for the next daily turn + NeuTTS. Mirrors the
        Hermes idle-persona watchdog; never crashes the loop."""
        interval = max(5.0, min(30.0, self._idle_swap_timeout_s / 4.0))
        logger.info(
            "router idle watchdog: timeout=%ss check_every=%.0fs idle_persona=%s",
            self._idle_swap_timeout_s,
            interval,
            self._idle_persona,
        )
        while True:
            try:
                await asyncio.sleep(interval)
                # Need to know the idle model, and currently be on a different
                # (heavier) one, and be past the idle threshold.
                if not self._idle_model_path:
                    continue
                if (
                    not self._loaded_model_path
                    or self._loaded_model_path == self._idle_model_path
                ):
                    continue
                if (time.monotonic() - self._last_activity) < self._idle_swap_timeout_s:
                    continue
                async with self._swap_lock:
                    idle_for = time.monotonic() - self._last_activity
                    if (
                        self._loaded_model_path
                        and self._loaded_model_path != self._idle_model_path
                        and idle_for >= self._idle_swap_timeout_s
                    ):
                        logger.info(
                            "router idle watchdog: %s idle %.0fs -> swap back to %s",
                            self._loaded_model_path,
                            idle_for,
                            self._idle_persona,
                        )
                        try:
                            await self._switch_persona(self._idle_persona)
                            self._loaded_model_path = self._idle_model_path
                            self.prompt_dialect = dialect_from_model(
                                self._idle_model_path
                            )
                            logger.info(
                                "router: prompt dialect %s for %s",
                                self.prompt_dialect.value,
                                self._idle_model_path,
                            )
                        except BrainError as exc:
                            logger.warning(
                                "router idle watchdog swap failed (will retry): %s", exc
                            )
            except asyncio.CancelledError:
                logger.info("router idle watchdog stopping")
                raise
            except Exception:  # noqa: BLE001 - never let the watchdog die
                logger.exception("router idle watchdog tick failed; continuing")

    async def _switch_persona(self, persona_name: str) -> None:
        """Tell the Rust supervisor to make `persona_name`'s model resident.

        Pings are disabled because Rust's WS handler blocks in ensure_started_for
        during a cold load and cannot answer them; the app-level switch_timeout_s
        governs how long we wait (mirrors hermes_gateway._switch_persona).
        """
        try:
            ws = await asyncio.wait_for(
                websockets.connect(
                    f"{self._switch_ws_url}/", ping_interval=None, ping_timeout=None
                ),
                timeout=10.0,
            )
        except (asyncio.TimeoutError, OSError) as exc:
            raise BrainError(
                f"router: cannot reach Rust WS at {self._switch_ws_url}: {exc}"
            ) from exc
        try:
            await ws.send(
                json.dumps({"action": "switch_persona", "persona_name": persona_name})
            )
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=self._switch_timeout_s)
            except asyncio.TimeoutError as exc:
                raise BrainError(
                    f"router: Rust did not ack switch to {persona_name!r} within "
                    f"{self._switch_timeout_s:.0f}s (model likely still loading)"
                ) from exc
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise BrainError(
                    f"router: non-JSON switch response: {raw[:200]!r}"
                ) from exc
            action = msg.get("action")
            if action == "error":
                raise BrainError(
                    f"router: Rust rejected switch to {persona_name!r}: "
                    f"{msg.get('message', '?')}"
                )
            if action != "persona_switched" or msg.get("status") != "success":
                raise BrainError(
                    f"router: unexpected switch response (action={action!r}): {msg}"
                )
            logger.info("router: persona_switched ok -> %s", persona_name)
        finally:
            try:
                await ws.close()
            except Exception:  # noqa: BLE001 - close is best-effort
                pass
