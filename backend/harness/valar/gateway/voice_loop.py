"""The clean voice loop.

assemble context (persona + Engram memory + bounded recent history)
  -> call BrainProvider (stream tokens)
  -> sentence-segment incrementally
  -> stream TTS per sentence
  -> emit speaking_complete

No band-aids: no history truncation beyond the sane token budget, no thinking
suppression as cost control, full telemetry per turn. The loop is transport-
agnostic — it takes an `emit` callback so it can be unit-tested without a socket.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import re
import time
from dataclasses import replace
from typing import Awaitable, Callable

from ..brain import BrainProvider, BrainStreamResult, ChatMessage, ChatOptions
from ..config import ValarConfig
from ..memory import EngramMemory
from ..persona import Persona
from ..telemetry import Timer, TurnTelemetry
from ..voice import NeuTTSStreamer, SentenceSegmenter
from .context import ContextAssembler, estimate_tokens
from .session import Session, State

logger = logging.getLogger("valar.voice_loop")

# emit(kind, payload) — kind is a protocol action name; payload is dict OR bytes.
Emit = Callable[[str, object], Awaitable[None]]

# Announced-but-not-executed detector (2026-07-29, the Coconut lesson: the
# model's deliberation must not TERMINATE in the speech channel). Matches an
# action announcement leading the reply — "allow me to consult...", "let me
# check...", "one moment while I pull up..." — the shape a model produces when
# it narrates the step instead of emitting the tool call (live: iOS session
# ec2deb7c, "Allow me to consult your memory" with tools_invoked=[]). Requires
# BOTH an intent lead and an action verb so "let me think"/"let me explain"
# never match.
_ANNOUNCE_RE = re.compile(
    r"\b(?:allow me to|let me|i(?:'ll| will)(?: just| now)?|one moment while i"
    r"|give me a (?:moment|second) (?:to|while i)|i shall)\s+(?:go\s+)?"
    r"(?:check|consult|look(?: (?:that|this|it))? up|look into|pull(?: up)?"
    r"|search|fetch|review|retrieve|dig|bring in|see what|find out"
    # Delegation shapes (live 2026-07-31: "I shall have Mentat forge a more
    # sophisticated..." with zero tool calls). The commission verbs.
    r"|have|ask|task|commission|forge|dispatch|start)\b",
    re.IGNORECASE,
)


class VoiceLoop:
    def __init__(
        self,
        config: ValarConfig,
        brain: BrainProvider,
        memory: EngramMemory,
        tts: NeuTTSStreamer,
    ):
        self.config = config
        self.brain = brain
        self.memory = memory
        self.tts = tts
        self.assembler = ContextAssembler(config.context)
        # The House Ledger (SCX v2): day-first decision records. The gateway
        # is the single writer; persona_dir.parent is the repo root.
        from ..ledger import Ledger

        self.ledger = Ledger(config.persona_dir.parent)

    @staticmethod
    def _classify_error(exc: BaseException) -> str:
        """Coarse error kind for the typed error event (Phase 1b). Intentionally
        few buckets: 'brain' (inference backend unreachable/failed), 'client_gone'
        (socket died mid-turn), 'internal' (everything else)."""
        mod = type(exc).__module__ or ""
        name = type(exc).__name__
        if name == "BrainError" or mod.startswith("httpx"):
            return "brain"
        if "Disconnect" in name or mod.startswith("websockets"):
            return "client_gone"
        return "internal"

    async def run_turn(
        self,
        session: Session,
        persona: Persona,
        user_text: str,
        emit: Emit,
        stt_ms: float = 0.0,
    ) -> None:
        """Execute one full voice turn for `user_text` and stream the reply.

        ``stt_ms`` is the transcription time measured by the CALLER (STT runs in
        server.py before this turn starts) so the per-stage telemetry is real;
        0.0 on the text paths (text_query / client_transcription) where Valar
        does no STT.

        Phase 1b: failures emit ONE typed `error` event (additive keys `stage`,
        `kind`, `partial` + telemetry snapshot on the existing error action) and
        re-raise for the caller's IDLE bookkeeping. A stream that dies after the
        first token marks the turn PARTIAL: the truncated reply is recorded in
        history with an explicit cut-off marker so the next turn's context (and
        the operator) knows the user heard an incomplete answer.
        """
        telemetry = TurnTelemetry(
            session_id=session.session_id,
            persona=persona.name,
            stt_mode=session.stt_mode,
        )
        telemetry.stt_ms = round(stt_ms, 2)
        # Mutable turn context shared with the streaming closure: `stage` tracks
        # where the turn is (for the typed error), `partial*` capture a stream
        # that died after first token.
        ctx: dict = {"stage": "start", "partial": False, "partial_text": ""}
        try:
            await self._run_turn_impl(session, persona, user_text, emit, telemetry, ctx)
        except Exception as exc:  # noqa: BLE001 - typed emit, then re-raise
            telemetry.error_stage = str(ctx["stage"])
            telemetry.error_kind = self._classify_error(exc)
            telemetry.partial = bool(ctx["partial"])
            if ctx["partial"] and ctx["partial_text"]:
                session.record_turn(
                    user_text,
                    str(ctx["partial_text"]) + " [answer cut off mid-delivery]",
                )
            telemetry.emit()  # a failed turn still logs its record
            with contextlib.suppress(Exception):  # socket may already be gone
                await emit(
                    "error",
                    {
                        "action": "error",
                        "message": str(exc),
                        "stage": telemetry.error_stage,
                        "kind": telemetry.error_kind,
                        "partial": telemetry.partial,
                        "context_fill_pct": telemetry.context_fill_pct,
                        "prompt_tokens_est": telemetry.prompt_tokens_est,
                        "tools_invoked": telemetry.tools_invoked,
                    },
                )
            # Callers (turn wrappers in server.py) skip their generic error
            # emit when the typed one already went out.
            exc._valar_error_emitted = True  # type: ignore[attr-defined]
            raise

    async def _run_turn_impl(
        self,
        session: Session,
        persona: Persona,
        user_text: str,
        emit: Emit,
        telemetry: TurnTelemetry,
        ctx: dict,
    ) -> None:

        # --- THINKING ---------------------------------------------------------
        session.state = State.THINKING
        await emit("thinking_message", {"action": "thinking_message", "persona_name": persona.name})

        # Ensure the active persona's cloned voice is encoded before we speak.
        # Cached after the first call per persona; encode_reference is GPU-heavy
        # so run it off the event loop.
        ctx["stage"] = "tts"
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            None,
            self.tts.sync_persona_voice,
            persona.voice_reference_audio,
            persona.voice_reference_text,
        )

        ctx["stage"] = "memory"
        memory_block = ""
        try:
            memory_block = self.memory.recall(user_text)
        except Exception as exc:  # noqa: BLE001 - memory is additive
            logger.warning("memory recall failed (continuing without): %s", exc)

        messages = self.assembler.build(
            system_prompt=persona.system_prompt,
            memory_block=memory_block,
            history=session.history,
            user_text=user_text,
            telemetry=telemetry,
            device_context=session.device_context,
            tool_specs=self._tool_priming_specs(persona, session),
        )

        # Persona-driven model routing + sampling. The "router" backend reads
        # persona_name + model_path (the persona's deep_model.path) to make the
        # right model resident before streaming; plain backends ("rust") ignore
        # them. Sampling/max_tokens follow the persona's deep_model so each model
        # gets its own tuned values (gemma-4-E4B daily vs a heavy Qwen worker),
        # falling back to the global Valar brain config when a persona omits them.
        dm = persona.config.get("deep_model") if isinstance(persona.config, dict) else None
        dm = dm if isinstance(dm, dict) else {}
        bc = self.config.brain
        opts = ChatOptions(
            max_tokens=int(dm.get("max_tokens", bc.max_tokens)),
            temperature=float(dm.get("temperature", bc.temperature)),
            top_p=float(dm.get("top_p", bc.top_p)),
            top_k=int(dm.get("top_k", bc.top_k)),
            model=bc.model,
            persona_name=persona.name,
            model_path=dm.get("path", ""),
            # The STREAMED spoken answer is always reflex: with the server on
            # --reasoning auto (2026-07-31), an unmarked request could think
            # into dead air before the first sentence. Decision calls override
            # this per persona below.
            enable_thinking=False,
        )

        # --- FLAG-GATED TOOL ROUND-TRIP (Keystone 2) --------------------------
        # Additive + opt-in. With HEARTH_TOOLS_ENABLED off (default) this whole
        # block is skipped: `messages` and the streaming call below are byte-for-
        # byte today's behavior. When enabled with a non-empty registry, run ONE
        # tool-aware (non-streaming) round-trip; if the brain called tools, the
        # results are appended and `messages` is replaced with the tool-augmented
        # list, which the existing streaming call then answers from (grounded).
        # Time the tool round-trip (decision call + handler execution) so we can
        # see whether it adds enough latency before the answer to warrant a spoken
        # "thinking" filler. 0.0 on the flag-OFF path (the call returns instantly).
        ctx["stage"] = "tool_round_trip"
        turn_decisions: list = []
        with Timer(telemetry, "tool_round_trip_ms"):
            messages, filler_task = await self._maybe_run_tools(
                messages, opts, telemetry, session, emit, persona,
                decisions_out=turn_decisions,
            )

        # Voice/screen split (2026-06-07): a grounded tool answer SPEAKS at most
        # a few sentences -- the composer's cards already carry the detail to
        # the screen, so the voice stops duplicating it (live finding: recall
        # answers rambled, bloated history, and fed the empty-answer failure).
        # The instruction rides the last tool message (template-safe, the
        # force-answer idiom) and the final call's token budget is capped.
        if telemetry.tools_invoked:
            # Screen-deflection honesty (2026-07-30): "the screen already shows
            # the details" is only true when a tool SUCCEEDED -- on an all-failed
            # turn the card carries no data, and deflecting to it reads as
            # misdirection (live: Sulivan pointed at an empty trading-desk card
            # twice). Failed turns get a say-it-plainly instruction instead.
            any_success = any(
                m.role == "tool"
                and not str(m.content or "").startswith("[tool error]")
                for m in messages
            )
            note = (
                "\n\n[Speak your answer in at most three short sentences. "
                "The screen already shows the details.]"
                if any_success
                else "\n\n[Speak your answer in at most three short sentences. "
                "The tool could not provide data -- say so plainly. Do NOT "
                "tell the user to check the screen; there is nothing on it.]"
            )
            for m in reversed(messages):
                if m.role == "tool":
                    m.content = (m.content or "") + note
                    break
            opts = replace(opts, max_tokens=min(opts.max_tokens, 220))

        # --- BRAIN STREAM + SENTENCE SEGMENTATION + TTS (PIPELINED) -----------
        # The brain producer streams tokens into a sentence queue; ONE consumer
        # task synthesizes each sentence in order while generation continues.
        # Before this, every sentence's TTS was awaited inside the token loop,
        # serializing generation and synthesis (live 2-sentence baseline:
        # brain_total 8394ms of which 8122ms was inline TTS) and polluting
        # brain_total_ms. Wire order is unchanged — tts_chunk_*/audio per
        # sentence (single consumer preserves sentence order), then ai_response,
        # then speaking_complete — only the overlap in time is new.
        async def _stream_once(
            msgs: list[ChatMessage], filler, time_it: bool
        ) -> tuple[str, int, BrainStreamResult]:
            """One streaming answer pass (producer + sentence queue + TTS
            consumer). Factored out so an empty grounded answer can be retried
            without duplicating the pipeline."""
            result = BrainStreamResult()
            segmenter = SentenceSegmenter()
            full_reply: list[str] = []
            first_token_seen = False

            queue: asyncio.Queue = asyncio.Queue()
            _DONE = object()

            async def _consume() -> int:
                speaking_started = False
                spoken = 0
                # The thinking filler (started during the tool round-trip) must
                # finish before the answer's first sentence so audio stays
                # strictly in order.
                if filler is not None:
                    with contextlib.suppress(Exception):
                        speaking_started, spoken = await filler
                while True:
                    item = await queue.get()
                    if item is _DONE:
                        return spoken
                    speaking_started, spoken = await self._speak(
                        item, session, emit, speaking_started, spoken, telemetry
                    )

            consumer = asyncio.create_task(_consume())

            t_brain0 = time.monotonic()
            try:
                timer = (
                    Timer(telemetry, "brain_total_ms")  # pure generation time
                    if time_it
                    else contextlib.nullcontext()
                )
                with timer:
                    stream = self.brain.chat(msgs, opts, result)
                    async for delta in stream:
                        if not first_token_seen:
                            first_token_seen = True
                            if time_it:
                                # Real first-token latency. (Was read from
                                # brain_total_ms, which the Timer only writes on
                                # EXIT — always logged 0.0.)
                                telemetry.brain_first_token_ms = round(
                                    (time.monotonic() - t_brain0) * 1000.0, 2
                                )
                        full_reply.append(delta)
                        for sentence in segmenter.feed(delta):
                            queue.put_nowait(sentence)
                    tail = segmenter.flush()
                    if tail:
                        queue.put_nowait(tail)
                queue.put_nowait(_DONE)
                spoken = await consumer
            except BaseException:
                # Producer failed (brain error, client gone): stop the consumer
                # so no orphan task keeps emitting into a dead turn, re-raise.
                # Phase 1b: if tokens already streamed, the user may have heard
                # part of the answer — capture it so the turn is marked PARTIAL.
                if full_reply:
                    ctx["partial"] = True
                    ctx["partial_text"] = "".join(full_reply).strip()
                consumer.cancel()
                with contextlib.suppress(BaseException):
                    await consumer
                raise
            return "".join(full_reply).strip(), spoken, result

        ctx["stage"] = "brain_stream"
        reply_text, sentences_spoken, result = await _stream_once(
            messages, filler_task, time_it=True
        )

        # A grounded tool turn must end in spoken prose. An empty stream here is
        # the 2026-06-05 failure (the model emitted tool syntax into the final
        # call, parsed away to nothing; the user heard only the filler). Live
        # 2026-06-07: two consecutive recall turns died silent. Until the
        # gemma-4 agentic-token/template investigation lands, retry ONCE with an
        # explicit answer-now nudge; if still empty, speak an apology rather
        # than leave the user in silence.
        # Raw gemma tool-call syntax in the FINAL stream is the same failure as
        # an empty answer wearing a costume (live 2026-07-20: the client heard
        # "<|tool_call>call:mentat_status{}" spoken aloud). Treat it as empty so
        # the nudge-retry path below catches both shapes.
        syntax_leak = bool(reply_text) and (
            "<|tool_call" in reply_text or "<tool_call|" in reply_text
            or reply_text.strip().startswith("call:")
        )
        if syntax_leak:
            logger.warning("final answer was raw tool syntax; treating as empty: %r",
                           reply_text[:120])
            reply_text = ""

        if not reply_text and (telemetry.tools_invoked or syntax_leak):
            logger.warning(
                "empty final answer after tool turn (tools=%s) — retrying with nudge",
                telemetry.tools_invoked,
            )
            nudge = ChatMessage(
                role="user",
                content=(
                    "[Answer my previous question now in plain spoken language, "
                    "using the tool results already provided. Do not call tools "
                    "or emit tool syntax.]"
                ),
            )
            reply_text, more_spoken, result = await _stream_once(
                messages + [nudge], None, time_it=False
            )
            sentences_spoken += more_spoken
            if reply_text:
                logger.info("nudge retry produced prose (%d chars)", len(reply_text))
            else:
                logger.warning("nudge retry still empty — speaking the fallback")
                reply_text = "I found the information, but lost my words. Could you ask me that again?"
                _, sentences_spoken = await self._speak(
                    reply_text, session, emit, True, sentences_spoken, telemetry
                )

        # Announced-but-not-executed guard (2026-07-29): the model said it would
        # check something but called no tool — the announcement was already
        # spoken (streaming TTS), so make it HONEST: run the tool round-trip
        # now with an act-now instruction and speak the real answer as the
        # follow-through. One retry, tool turns excluded (they already acted).
        if (
            reply_text
            and not telemetry.tools_invoked
            and len(reply_text) < 240
            and _ANNOUNCE_RE.search(reply_text[:90])
        ):
            logger.warning(
                "announced action with no tool call — following through: %r",
                reply_text[:120],
            )
            follow_msgs = messages + [
                ChatMessage(role="assistant", content=reply_text),
                ChatMessage(
                    role="user",
                    content=(
                        "[You announced an action but no tool was called. Call "
                        "the needed tool NOW and answer from its result — or "
                        "answer directly from what you know. Do not repeat the "
                        "announcement; do not announce again.]"
                    ),
                ),
            ]
            with Timer(telemetry, "tool_round_trip_ms"):
                follow_msgs, follow_filler = await self._maybe_run_tools(
                    follow_msgs, opts, telemetry, session, emit, persona,
                    decisions_out=turn_decisions,
                )
            follow_text, more_spoken, _ = await _stream_once(
                follow_msgs, follow_filler, time_it=False
            )
            sentences_spoken += more_spoken
            if follow_text:
                logger.info(
                    "follow-through produced prose (%d chars, tools=%s)",
                    len(follow_text),
                    telemetry.tools_invoked,
                )
                reply_text = (reply_text + " " + follow_text).strip()

        # Diagnosis visibility: the spoken answer's head goes to the journal on
        # EVERY turn (2026-07-31 -- a promise spoken on a no-tool turn was only
        # findable via a TTS line; no-tool turns were invisible).
        logger.info("final answer (tools=%s): %r",
                    telemetry.tools_invoked, reply_text[:200])

        # The House Ledger decision record (SCX v2 emitter #1): question,
        # per-round reasoning + tool choices, what actually ran, answer head.
        self.ledger.decision(
            session=session.session_id,
            persona=persona.name,
            question=user_text,
            decisions=turn_decisions,
            tools_invoked=list(telemetry.tools_invoked),
            answer_head=reply_text,
        )

        # Send the full text response (ai_response) for clients that display text.
        await emit(
            "ai_response",
            {
                "action": "ai_response",
                "text": reply_text,
                "persona_name": persona.name,
                "model_used": result.model_used,
            },
        )

        # --- SPEAKING COMPLETE ------------------------------------------------
        await emit("speaking_complete", {"action": "speaking_complete"})
        session.state = State.IDLE
        session.record_turn(user_text, reply_text)

        # --- TELEMETRY --------------------------------------------------------
        telemetry.sentences_spoken = sentences_spoken
        cpt = self.config.context.chars_per_token
        telemetry.completion_tokens_est = (
            result.usage.completion_tokens or estimate_tokens(reply_text, cpt)
        )
        if result.usage.prompt_tokens:
            telemetry.prompt_tokens_est = result.usage.prompt_tokens
        telemetry.emit()

    @staticmethod
    def _persona_tool_grants(persona: Persona) -> dict | None:
        """The persona's catalog grants (`tool_grants` in persona.json:
        {"domains": [...], "allow": [...], "deny": [...]}). Absent key -> None ->
        the full registry (backward compatible). The per-persona tool-subset
        seam: selection reliability degrades with tool-set size (measured
        2026-06-05; wiki tool-catalog.md), so each persona is granted only the
        domains it actually serves."""
        cfg = persona.config if isinstance(persona.config, dict) else {}
        grants = cfg.get("tool_grants")
        return grants if isinstance(grants, dict) else None

    def _tool_priming_specs(self, persona: Persona, session: Session):
        """The enabled tools' (name, description) for the system-prompt priming
        block, resolved through the persona's grants AND the session's client
        capabilities so the priming matches exactly what the decision call is
        offered. Harness-level: lives in Valar so every client gets identical
        tool awareness (no per-client logic). None when tools are off — keeping
        the flag-OFF prompt byte-identical to today. The brief YAML read mirrors
        the one in _maybe_run_tools; both stay off the path when the flag is off."""
        try:
            from ..tools import resolve_registry, tools_enabled

            if not tools_enabled():
                return None
            reg = resolve_registry(
                self._persona_tool_grants(persona), session.capabilities
            )
            specs = [
                (s["function"]["name"], s["function"].get("description", ""))
                for s in reg.schemas()
                if s.get("function", {}).get("name")
            ]
            return specs or None
        except Exception as exc:  # noqa: BLE001 - priming is additive, never fatal
            logger.warning("tool priming specs unavailable: %s", exc)
            return None

    async def _maybe_run_tools(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        telemetry: TurnTelemetry,
        session: Session,
        emit: Emit,
        persona: Persona,
        decisions_out: list | None = None,
    ) -> tuple[list[ChatMessage], "asyncio.Task | None"]:
        """Flag-gated tool round-trip. Returns `(messages, filler_task)`:
        `messages` unchanged when the tool layer is disabled (default) or no tool
        was called, so the streaming final answer is identical to today; when
        enabled and the brain calls a tool, the returned list carries the
        assistant tool-call turn + role="tool" results so the existing streaming
        call answers grounded.

        `filler_task` is the in-flight spoken thinking filler (the tool's
        `speak:` phrase from tools.yaml), started the moment the brain decided to
        call a tool so its synthesis overlaps the handler execution; None when no
        tool fired or none defines a phrase. The answer consumer awaits it before
        the first answer sentence so audio stays in order.

        Imports are local so the tools package is never imported on the flag-OFF
        path, and the brain must expose `chat_tools` (router/rust do). Any failure
        degrades to the original messages — the voice turn never breaks for tools.
        """
        # Lazy import: keeps the tools package off the default voice-turn path.
        from ..tools import resolve_registry, tools_enabled
        from ..tools.loop import maybe_run_tools

        if not tools_enabled():
            return messages, None
        registry = resolve_registry(
            self._persona_tool_grants(persona), session.capabilities
        )
        if not registry.names():
            return messages, None
        chat_tools = getattr(self.brain, "chat_tools", None)
        if chat_tools is None:
            logger.warning("tools enabled but brain has no chat_tools; skipping")
            return messages, None

        # Convert ChatMessage <-> dict for the tool loop (loop.py works on dicts).
        msgs_dict: list[dict] = [
            {
                "role": m.role,
                "content": m.content,
                **({"tool_calls": m.tool_calls} if m.tool_calls is not None else {}),
                **({"tool_call_id": m.tool_call_id} if m.tool_call_id is not None else {}),
                **({"name": m.name} if m.name is not None else {}),
            }
            for m in messages
        ]

        # Persona-scoped decision behavior (tasks/sulivan-reasoning.md):
        # `tool_loop.reasoning` turns thinking ON for the non-streaming
        # decision calls ONLY (the filler covers the latency; the streamed
        # answer stays reflex via enable_thinking=False in run_turn), and
        # `tool_loop.max_rounds` raises the round budget so the discovery
        # chain (consult -> list_cards -> forge_card) fits in one turn.
        tl = persona.config.get("tool_loop") if isinstance(persona.config, dict) else None
        tl = tl if isinstance(tl, dict) else {}
        decision_opts = (
            replace(opts, enable_thinking=True) if tl.get("reasoning") else opts
        )
        from ..tools.loop import MAX_TOOL_ROUNDS as _DEFAULT_ROUNDS

        max_rounds = int(tl.get("max_rounds", _DEFAULT_ROUNDS))

        async def brain_tool_call(msgs: list[dict], tools: list[dict]) -> dict:
            chat_msgs = [
                ChatMessage(
                    role=d.get("role", "user"),
                    content=d.get("content") or "",
                    tool_calls=d.get("tool_calls"),
                    tool_call_id=d.get("tool_call_id"),
                    name=d.get("name"),
                )
                for d in msgs
            ]
            r = await chat_tools(chat_msgs, decision_opts, tools)
            return {
                "content": (r or {}).get("content") or "",
                "tool_calls": (r or {}).get("tool_calls") or [],
                "reasoning": (r or {}).get("reasoning") or "",
            }

        # Thinking filler: fired by the loop the moment the brain's first response
        # carries tool_calls, BEFORE the handlers run — so the phrase synthesizes
        # and plays while the tool executes (the gap it exists to cover). The task
        # is returned to run_turn; the answer consumer joins it for audio order.
        filler_holder: dict = {"task": None}

        async def _emit_stage(stage: str) -> None:
            # State-machine sub-stage events (Phase B, 2026-06-06): the notify
            # track. Clients animate per sub-stage; unknown stages are ignored.
            try:
                await emit(
                    "state_update",
                    {"action": "state_update", "state": "thinking", "stage": stage},
                )
            except Exception as exc:  # noqa: BLE001 - events never break the turn
                logger.warning("state_update emit failed: %s", exc)

        async def on_tool_calls(names: list) -> None:
            # "consulting" = a persona subagent is working (consult_memory ->
            # Selene); everything else is plain handler execution ("acting").
            await _emit_stage(
                "consulting" if "consult_memory" in names else "acting"
            )
            # Status visibility (2026-07-31): tell clients WHICH tools are
            # running so the status bar can say "ringing the trading desk"
            # instead of a generic thinking state. Cosmetic; never breaks.
            try:
                await emit(
                    "pipeline_stage",
                    {
                        "action": "pipeline_stage",
                        "stage": "tools",
                        "event": "invoke",
                        "tools": [n for n in names if n],
                    },
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("tool-activity emit failed: %s", exc)
            phrase = registry.speak_phrase(names)
            if phrase and filler_holder["task"] is None:
                filler_holder["task"] = asyncio.create_task(
                    self._speak(phrase, session, emit, False, 0, telemetry)
                )

        # Generative UI (Phase C): the COMPOSER is the single author of
        # ui_component traffic -- the loop feeds it each executed tool result
        # and emits whatever ops it returns (typed-card passthrough + the
        # generated_view brief fallback in rule-based v1; a model-driven
        # composer replaces the internals behind the same seam). Emission is
        # gated on the client's ui_render capability; the tools themselves
        # stay universal, so non-UI clients keep identical voice behavior.
        from .composer import compose_for_result

        ui_enabled = bool(session.capabilities.get("ui_render"))

        async def on_tool_result(name: str, result) -> None:
            if not ui_enabled:
                return
            for op in compose_for_result(name, result):
                try:
                    await emit("ui_component", {"action": "ui_component", **op})
                    logger.info(
                        "ui_component emitted: %s (tool=%s)",
                        op.get("type") or op.get("op"),
                        name,
                    )
                except Exception as exc:  # noqa: BLE001 - UI never breaks the turn
                    logger.warning("ui_component emit failed for %s: %s", name, exc)

        # maybe_run_tools mutates msgs_dict IN PLACE and returns the same list, so
        # capture the original length first to detect whether any tool turn was
        # appended (augmented IS msgs_dict; comparing their lengths would be a no-op).
        original_len = len(msgs_dict)
        await _emit_stage("deciding")
        try:
            augmented = await maybe_run_tools(
                msgs_dict, brain_tool_call, registry, on_tool_calls, on_tool_result,
                max_rounds=max_rounds, decisions_out=decisions_out,
            )
        except Exception as exc:  # noqa: BLE001 - tools must never break the turn
            logger.error("tool round-trip failed; answering without tools: %s", exc)
            return messages, filler_holder["task"]

        # No tool was called => no messages appended => nothing to rebuild (fast path).
        if len(augmented) == original_len:
            return messages, filler_holder["task"]

        tool_names = [
            d.get("name", "") for d in augmented if d.get("role") == "tool"
        ]
        telemetry.tools_invoked = [n for n in tool_names if n]
        logger.info("tools invoked this turn: %s", telemetry.tools_invoked)

        return [
            ChatMessage(
                role=d.get("role", "user"),
                content=d.get("content") or "",
                tool_calls=d.get("tool_calls"),
                tool_call_id=d.get("tool_call_id"),
                name=d.get("name"),
            )
            for d in augmented
        ], filler_holder["task"]

    async def say(self, session: Session, persona, text: str, emit: Emit) -> None:
        """Speak `text` verbatim in the persona voice, with NO LLM turn. Used for
        short client-driven UI cues (e.g. the visionOS immersive-mode switch).
        Streams over the normal tts path so clients render + play it unchanged.
        """
        text = (text or "").strip()
        if not text:
            return
        sr = self.config.voice.output_sample_rate
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            None,
            self.tts.sync_persona_voice,
            persona.voice_reference_audio,
            persona.voice_reference_text,
        )
        session.state = State.SPEAKING
        await emit(
            "tts_chunk_start",
            {"action": "tts_chunk_start", "seg_idx": 0, "sample_rate": sr, "text": text},
        )
        try:
            async for pcm in self.tts.stream_sentence(text):
                await emit("audio", pcm)
        except Exception as exc:  # noqa: BLE001 - surface but don't wedge the session
            logger.error("say() TTS failed: %s", exc)
            await emit("tts_error", {"action": "tts_error", "message": str(exc), "seg_idx": 0})
        await emit("tts_chunk_end", {"action": "tts_chunk_end", "seg_idx": 0})
        await emit("speaking_complete", {"action": "speaking_complete"})
        session.state = State.IDLE

    async def _speak(
        self,
        sentence: str,
        session: Session,
        emit: Emit,
        speaking_started: bool,
        sentences_spoken: int,
        telemetry: TurnTelemetry,
    ) -> tuple[bool, int]:
        """Stream one sentence's TTS as PCM chunks (tts_chunk_start/binary/end)."""
        sr = self.config.voice.output_sample_rate
        if not speaking_started:
            session.state = State.SPEAKING
        seg_idx = sentences_spoken
        # Carry the sentence text on its chunk_start so the client can show the
        # assistant text in step with speech (the full ai_response only arrives
        # after generation completes — too late for the chat to keep pace).
        await emit(
            "tts_chunk_start",
            {
                "action": "tts_chunk_start",
                "seg_idx": seg_idx,
                "sample_rate": sr,
                "text": sentence,
            },
        )
        with Timer(telemetry, "tts_total_ms", accumulate=True):  # summed across sentences
            try:
                async for pcm in self.tts.stream_sentence(sentence):
                    await emit("audio", pcm)  # binary PCM frame
            except Exception as exc:  # noqa: BLE001 - surface but keep turn alive
                logger.error("TTS failed for sentence: %s", exc)
                await emit(
                    "tts_error",
                    {"action": "tts_error", "message": str(exc), "seg_idx": seg_idx},
                )
        await emit("tts_chunk_end", {"action": "tts_chunk_end", "seg_idx": seg_idx})
        return True, sentences_spoken + 1
