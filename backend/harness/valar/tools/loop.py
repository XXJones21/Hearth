"""Tool-calling loop (Keystone 2) -- the additive, opt-in function-call seam.

This is the *design + minimal scaffold* for the one-round-trip tool loop the
daily model runs before its final answer ("turn on the lights", "set a timer",
"what's the weather"). It is intentionally NOT wired into
``voice_loop.run_turn`` -- wiring it is a deliberate, flag-gated follow-up so the
working voice turn cannot regress.

Design (from proactive-tools-roadmap.md, Keystone 2):

  1. Valar assembles the prompt as today, but ALSO passes ``registry.schemas()``
     as the function-calling ``tools=[...]`` on the brain request.
  2. The brain either answers directly (no tool needed -> nothing changes) or
     emits one or more ``tool_calls``.
  3. For each tool call, Valar runs ``registry.invoke(name, args)`` (handlers run
     in a thread; they never touch the loop/socket/brain) and appends the result
     as a ``role: "tool"`` message.
  4. Valar calls the brain ONE more time with the tool results appended; that
     second response is the final answer, which flows into the existing
     sentence-segment -> TTS path unchanged.

Latency split: fast reactive tools take this single round-trip on the daily
model; hard/multi-step questions escalate to the Fennec ``reason`` subagent
(roadmap Tier 3). "Turn on the lights" must never traverse the five-stage pipeline.

Integration note (why this is not wired yet): the current ``BrainProvider.chat``
streams plain text deltas and has no ``tools=`` parameter or ``tool_calls`` parse
path. Wiring this requires (a) a non-streaming (or tool-aware) brain call that
surfaces ``tool_calls`` and (b) a ``ChatOptions.tools`` field. Both are additive
to the brain seam and must land behind ``HEARTH_TOOLS_ENABLED`` with the voice path
defaulting to today's tool-free behavior. Until then this module documents the
contract and offers ``maybe_run_tools`` as the seam a future gateway change calls.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from . import ToolRegistry, tools_enabled

logger = logging.getLogger("valar.tools.loop")

# Cap tool round-trips per turn so a model that loops on tool calls cannot stall a
# voice turn. The reactive design is ONE round-trip; allow a small margin.
# Persona-overridable since 2026-07-31 (tool_loop.max_rounds): the discovery
# chain (consult -> list_cards -> forge_card) needs 3+, and the fixed cap of 2
# was the structural blocker in the live 12:01 turn.
MAX_TOOL_ROUNDS = 2


class ToolCallingLoop:
    """Runs the tool round-trip against a tool-aware brain call.

    ``brain_tool_call`` is an injected async callable:
        await brain_tool_call(messages, tools) -> {content, tool_calls}
    where ``tool_calls`` is the OpenAI shape
    ``[{id, function: {name, arguments(json str)}}]``. Injecting it keeps this
    module decoupled from the streaming voice path and unit-testable with a fake.
    """

    def __init__(self, registry: ToolRegistry, max_rounds: int = MAX_TOOL_ROUNDS):
        self.registry = registry
        self.max_rounds = max(1, int(max_rounds))
        # Decision records for the turn: one {round, reasoning, tools} per
        # brain response that carried tool calls (SCX v2 / ledger exhaust).
        self.decisions: list[dict[str, Any]] = []

    async def run(
        self,
        messages: list[dict[str, Any]],
        brain_tool_call,
        on_tool_calls=None,
        on_tool_result=None,
    ) -> list[dict[str, Any]]:
        """Execute up to MAX_TOOL_ROUNDS of tool calls, mutating + returning the
        messages list with any ``role: "tool"`` results appended. The caller then
        does its normal streaming final-answer brain call on the returned messages.
        A no-tool response leaves messages untouched (the common fast path).

        ``on_tool_calls(names)`` is an optional async callback fired ONCE, on the
        first round's tool calls, BEFORE the handlers execute — the seam the voice
        loop uses to start a spoken thinking filler that overlaps the tool work.
        It is cosmetic: any failure is logged and the round-trip continues.

        ``on_tool_result(name, result)`` is an optional async callback fired for
        EVERY executed handler, right after it returns — the seam the voice loop
        uses to translate ``ToolResult.data`` payloads (e.g. ``ui_component``
        cards) into WS emits. Dropped duplicates never reach it. Like the filler
        callback it is cosmetic: failures are logged, the round-trip continues.

        Duplicate-call guard (2026-06-05): the first live gemma-4-12b turn called
        get_weather, got the result, then asked for the SAME call again instead of
        answering — exhausting the rounds and then emitting tool syntax into the
        final stream (an empty spoken answer). So: a call identical to one already
        executed this turn (same name + same arguments) is dropped, and when a
        round contains ONLY repeats — or the round cap is hit with calls still
        coming — the loop stops and appends an answer-now instruction to the last
        tool result (template-safe: tool content, not a trailing system message)
        so the final streaming call produces prose."""
        if not self.registry.names():
            return messages
        tools = self.registry.schemas()
        seen_calls: set[tuple[str, str]] = set()
        force_answer = False
        for round_idx in range(self.max_rounds):
            response = await brain_tool_call(messages, tools)
            tool_calls = (response or {}).get("tool_calls") or []
            reasoning = str((response or {}).get("reasoning") or "")
            if reasoning or tool_calls:
                self.decisions.append({
                    "round": round_idx + 1,
                    "reasoning": reasoning[:2000],
                    "tools": [
                        (c.get("function") or {}).get("name", "")
                        for c in tool_calls
                    ],
                })
            if not tool_calls:
                break
            fresh_calls = []
            for call in tool_calls:
                fn = call.get("function", {})
                key = (fn.get("name", ""), str(fn.get("arguments") or ""))
                if key in seen_calls:
                    logger.info("dropping duplicate tool call: %s", key[0])
                    continue
                seen_calls.add(key)
                fresh_calls.append(call)
            if not fresh_calls:
                # Only repeats left: the model is looping on tools, not answering.
                force_answer = True
                break
            names = [
                (c.get("function") or {}).get("name", "") for c in fresh_calls
            ]
            logger.info("tool round %d: %s", round_idx + 1, [n for n in names if n])
            if round_idx == 0 and on_tool_calls is not None:
                try:
                    await on_tool_calls([n for n in names if n])
                except Exception as exc:  # noqa: BLE001 - filler never breaks tools
                    logger.warning("on_tool_calls callback failed: %s", exc)
            # The assistant turn that issued the tool calls must precede the
            # tool results in the message list (OpenAI contract). Carry only the
            # calls actually executed so every tool_call id has a matching result.
            messages.append({"role": "assistant", "content": response.get("content") or "", "tool_calls": fresh_calls})
            for call in fresh_calls:
                fn = call.get("function", {})
                name = fn.get("name", "")
                raw_args = fn.get("arguments") or "{}"
                try:
                    args = json.loads(raw_args) if isinstance(raw_args, str) else dict(raw_args)
                except Exception:  # noqa: BLE001
                    args = {}
                result = await self.registry.invoke(name, args)
                if on_tool_result is not None:
                    try:
                        await on_tool_result(name, result)
                    except Exception as exc:  # noqa: BLE001 - emits never break tools
                        logger.warning("on_tool_result callback failed: %s", exc)
                # Phase 1c: a failed tool must be structurally legible. Before
                # this, ok=False was dropped here and the model read the error
                # string as if it were data (and could present it as an answer).
                # The marker + instruction make failure unmistakable while the
                # turn still survives (the existing recovery contract).
                content = result.content
                if not result.ok:
                    content = (
                        "[tool error] " + (content or "unknown error")
                        + "\n[This tool call FAILED. Do not present the text "
                        "above as data. Briefly acknowledge you could not do "
                        "it, and answer from what you already know.]"
                    )
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call.get("id", ""),
                        "name": name,
                        "content": content,
                    }
                )
            if round_idx == self.max_rounds - 1:
                force_answer = True
        if force_answer and messages and messages[-1].get("role") == "tool":
            messages[-1]["content"] = (
                str(messages[-1].get("content") or "")
                + "\n\n[All tool calls are complete. Answer the user now in plain "
                "spoken language using the results above. Do not call any more tools.]"
            )
        return messages


async def maybe_run_tools(
    messages: list[dict[str, Any]],
    brain_tool_call,
    registry: ToolRegistry | None = None,
    on_tool_calls=None,
    on_tool_result=None,
    max_rounds: int = MAX_TOOL_ROUNDS,
    decisions_out: list | None = None,
):
    """Opt-in entry point a future gateway can call before the streaming answer.

    Returns the (possibly tool-augmented) messages. A no-op -- returns messages
    unchanged -- when tools are disabled or the registry is empty, so callers can
    invoke it unconditionally without changing today's behavior. ``on_tool_calls``
    (the thinking-filler seam) and ``on_tool_result`` (the ToolResult.data /
    ui_component seam) are forwarded to the loop. ``decisions_out``, when given,
    receives the per-round {round, reasoning, tools} records (the ledger seam)."""
    if not tools_enabled():
        return messages
    reg = registry or ToolRegistry.from_yaml()
    if not reg.names():
        return messages
    loop = ToolCallingLoop(reg, max_rounds=max_rounds)
    out = await loop.run(messages, brain_tool_call, on_tool_calls, on_tool_result)
    if decisions_out is not None:
        decisions_out.extend(loop.decisions)
    return out
