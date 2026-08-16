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
from ..brain.prompt_dialect import dialect_from_model
from ..config import ValarConfig
from ..config.settings import hearth_engram
from ..memory import EngramMemory
from ..persona import Persona
from ..telemetry import Timer, TurnTelemetry
from ..voice import SentenceSegmenter
from .context import ContextAssembler, estimate_tokens
from . import first_run
from .session import Session, State
from ..models import resolve as resolve_model

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
    r"(?:(?:begin|start)(?:\s+by)?\s+)?"
    r"(?:check|consult|look(?: (?:that|this|it))? up|look into|pull(?: up)?"
    r"|search|fetch|review|retrieve|examine|read|dig|bring in|see what|find out"
    # Delegation shapes (live 2026-07-31: "I shall have Mentat forge a more
    # sophisticated..." with zero tool calls). The commission verbs.
    r"|have|ask|task|commission|forge|dispatch|start"
    # Presentation shapes (live 2026-08-07: "I shall present a selection of
    # archetypes" with zero tool calls, while choice_card sat unused).
    r"|present|offer|show|display|put)\b",
    re.IGNORECASE,
)

# A tool call written into the TEXT channel: gemma's "call:name{json}" shape,
# with or without its <|tool_call> marker. Used twice: to mute the TTS queue
# the moment syntax appears mid-stream (the person should never hear JSON),
# and to SALVAGE the call afterwards — the model that does this composed real
# arguments, and honoring them beats apologizing for them.
_TEXT_TOOL_CALL_RE = re.compile(r"call:([A-Za-z_]\w*)\s*\{")
_SYNTAX_SENTENCE_RE = re.compile(
    r"<\|?tool_call|<tool_call\||call:[A-Za-z_]\w*\s*\{|\[call:"
)

# The voice performs these; the eyes should not read them. Every text-channel
# emission is stripped of them while the TTS request keeps them -- the exact
# split the tags exist for. Mirrors the vocabulary create_persona teaches and
# OmniVoice's supported set.
_NONVERBAL_TAG_RE = re.compile(
    r"\[(?:laughter|sigh|confirmation-en|question-(?:en|ah|oh|ei|yi)"
    r"|surprise-(?:ah|oh|wa|yo)|dissatisfaction-hnn)\]"
)
# A tool call written as prose in brackets ('[call: start_project(input="")]',
# live 2026-08-08). Invented argument names, usually empty: not salvageable,
# so it is erased from the text channel and never spoken (the syntax regex
# above mutes it from the TTS queue).
_PSEUDO_CALL_RE = re.compile(r"\[call:\s*[A-Za-z_]\w*\s*\([^)\]]*\)\s*\]")

# Markup / code that must never go through TTS (live: Sulivan spoke a full
# HTML resume after read_file, and the engine then crashed on bare <style>
# tags). The file tools made this reachable; it is not specific to them.
_MARKUP_SPEAK_RE = re.compile(
    r"(?is)^(?:<!DOCTYPE\b|<html\b|<head\b|<body\b|<style\b|<script\b|"
    r"</(?:html|head|body|style|script)\b|"
    r"(?:html|head|body|style|script)\s*\{)"
)
_TAGGY_RE = re.compile(r"<[^>]+>")


def _skip_tts_sentence(sentence: str) -> bool:
    """True when a streamed sentence looks like markup/CSS, not speech."""
    s = (sentence or "").strip()
    if not s:
        return True
    if _MARKUP_SPEAK_RE.match(s):
        return True
    if s.count("<") >= 2 and len(_TAGGY_RE.findall(s)) >= 2:
        return True
    # A bare channel header. Gemma 4 opens its reasoning with the word
    # "thought" on its own line; the filter treats it as a skip so the
    # person never hears the channel name announced.
    if s.lower() == "thought":
        return True
    # CSS declaration blobs: property: value; { }
    if "{" in s and "}" in s and ":" in s:
        lower = s.lower()
        if any(
            k in lower
            for k in (
                "margin",
                "padding",
                "font-",
                "color:",
                "background",
                "display:",
                "flex",
                "width:",
                "height:",
            )
        ):
            return True
    return False


def sanitize_display_text(text: str) -> str:
    """The text channel's version of a reply: performed tags and pseudo-call
    brackets removed, whitespace tidied. TTS input never passes through this."""
    out = _NONVERBAL_TAG_RE.sub("", text)
    out = _PSEUDO_CALL_RE.sub("", out)
    out = re.sub(r"[ \t]{2,}", " ", out)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip()


def _balanced_json(text: str, start: int) -> str | None:
    """The {...} object starting at `start`, honoring strings and escapes;
    None when the braces never close (a truncated stream)."""
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(text)):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


class VoiceLoop:
    def __init__(
        self,
        config: ValarConfig,
        brain: BrainProvider,
        memory: EngramMemory,
        # Any streamer with the say/stream surface. NeuTTS left with the
        # migration; remote OmniVoice is the shipped arrangement.
        tts: object,
        # PersonaEngine, for the first-run handover: the commit turn switches
        # the session's speaker to the persona it just created. Optional so
        # headless proofs can run without one.
        personas: object | None = None,
    ):
        self.config = config
        self.brain = brain
        self.memory = memory
        self.tts = tts
        self.personas = personas
        self.assembler = ContextAssembler(config.context)
        # Beat three, opened by the client's sentinel and closed by the first
        # project existing. See first_run.BRAIN_KICKOFF for why this is a flag
        # plus a disk check rather than derived state alone: derived alone
        # re-triggers for anyone who later deletes their last project.
        self._brain_beat = False
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
        # First-run dispatch. The kickoff sentinel gets the scripted
        # walkthrough (product copy, no LLM call). The voice-check greeting
        # stays on the normal streaming path with a minimal direction. Every
        # OTHER first-run turn is a structured interview turn: one grammar-
        # constrained call whose JSON reply carries the speech, the card, and
        # eventually the commit -- tool selection by a 12B was
        # non-deterministic three different ways, and the schema replaces all
        # three guards with a certainty.
        impl = self._run_turn_impl
        if first_run.active(self.config.persona_dir):
            if first_run.is_kickoff(user_text):
                await self._scripted_opening(session, persona, emit)
                return
            if not first_run.is_voice_check(user_text):
                impl = self._structured_interview_turn
        elif first_run.is_brain_kickoff(user_text):
            # Beat three opens. First run is already over by construction --
            # the new resident ended it -- so this is the normal path with a
            # direction and two tools, held open until a project exists.
            self._brain_beat = True
            # The screen's furniture (mockup 14): the real root and folder
            # counts, rendered by the client beside the beat rather than
            # spoken. Product data the model never has to get right.
            await self._emit_brain_info(emit)

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
            await impl(session, persona, user_text, emit, telemetry, ctx)
        except Exception as exc:  # noqa: BLE001 - typed emit, then re-raise
            telemetry.error_stage = str(ctx["stage"])
            telemetry.error_kind = self._classify_error(exc)
            telemetry.partial = bool(ctx["partial"])
            if ctx["partial"] and ctx["partial_text"]:
                session.record_turn(
                    user_text,
                    str(ctx["partial_text"]) + " [answer cut off mid-delivery]",
                    persona.name,
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
            memory_block = self.memory.recall(
                user_text, project_hint=getattr(session, "topic_hint", None)
            )
        except Exception as exc:  # noqa: BLE001 - memory is additive
            logger.warning("memory recall failed (continuing without): %s", exc)

        # First run on the normal path is the voice-check greeting; it gets
        # the minimal direction. The full interview direction (which describes
        # the structured reply form) belongs to the structured turns only.
        system_prompt = persona.system_prompt
        if first_run.active(self.config.persona_dir):
            system_prompt = system_prompt + "\n\n" + first_run.GREETING_DIRECTION
        elif self._in_brain_beat():
            system_prompt = system_prompt + "\n\n" + first_run.BRAIN_DIRECTION

        messages = self.assembler.build(
            system_prompt=system_prompt,
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
            model_path=resolve_model(dm),
            # The STREAMED spoken answer is always reflex: with the server on
            # --reasoning auto (2026-07-31), an unmarked request could think
            # into dead air before the first sentence. Decision calls override
            # this per persona below.
            enable_thinking=False,
        )
        # The prompt dialect follows the resident GGUF: OpenAI messages stay the
        # intermediate form, and Gemma 4 renders its own turn tokens instead.
        self.assembler.set_dialect(dialect_from_model(opts.model_path))

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
        # A few tools act on the conversation rather than on the world, and the
        # model cannot pass them a session it does not know the id of.
        from ..tools.context import set_turn_context

        set_turn_context(
            session_id=session.session_id,
            persona=persona,
            brain=self.brain,
            config=self.config,
            personas=getattr(self, "personas", None),
        )
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
            # Once tool syntax appears in a sentence, nothing after it is
            # speech: the live 2026-08-07 turn spoke
            # '<|tool_call>call:choice_card{"question":' aloud because the
            # syntax guard only ran at end of stream. The full text still
            # accumulates for the salvage pass; only the audio is muted.
            muted = False

            queue: asyncio.Queue = asyncio.Queue()
            _DONE = object()

            async def _consume() -> int:
                speaking_started = False
                spoken = 0
                # The thinking filler (started during the tool round-trip) must
                # finish before the answer's first sentence so audio stays
                # strictly in order.
                if filler is not None:
                    # CancelledError is a BaseException, so suppress(Exception)
                    # does NOT catch it: a filler dropped because a card beat
                    # it would tear down this consumer and take the whole
                    # spoken answer with it. Caught by name, deliberately.
                    with contextlib.suppress(Exception, asyncio.CancelledError):
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
                            if not muted and _SYNTAX_SENTENCE_RE.search(sentence):
                                muted = True
                                logger.warning(
                                    "tool syntax reached the speech channel; muting TTS: %r",
                                    sentence[:80],
                                )
                            if not muted:
                                queue.put_nowait(sentence)
                    tail = segmenter.flush()
                    if tail:
                        if not muted and _SYNTAX_SENTENCE_RE.search(tail):
                            muted = True
                        if not muted:
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
            or _TEXT_TOOL_CALL_RE.search(reply_text) is not None
        )
        if syntax_leak:
            # First, honor the call if it can be honored: the model composed
            # real arguments in the wrong channel (live 2026-08-07, the
            # temperament card), and running them beats apologizing for them.
            salvaged = await self._salvage_text_tool_call(
                reply_text, session, emit, persona, telemetry
            )
            # Prose before the first syntax marker was real speech and has
            # already been heard; with the call honored it IS the answer.
            cut = len(reply_text)
            for mark in ("<|tool_call", "<tool_call|"):
                idx = reply_text.find(mark)
                if idx != -1:
                    cut = min(cut, idx)
            m_call = _TEXT_TOOL_CALL_RE.search(reply_text)
            if m_call is not None:
                cut = min(cut, m_call.start())
            prose = reply_text[:cut].strip()
            if salvaged and prose:
                logger.warning(
                    "tool syntax in final stream; call salvaged, prose kept: %r",
                    prose[:120],
                )
                reply_text = prose
            else:
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
            and _ANNOUNCE_RE.search(reply_text)
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

        # Interview card guard (2026-08-08): the third shape of the same
        # failure. A proper tool round renders the card; a call leaked into
        # the speech channel is salvaged; and sometimes the model asks its
        # question in clean prose and never reaches for the tool at all
        # (live: "How should their voice sound?" with tools=[]). During
        # first run every question owes the person choices, so a cardless
        # question gets one forced tool round. The question is already
        # spoken; the follow-up asks ONLY for the call and adds no speech.
        if (
            reply_text
            and "?" in reply_text
            and not telemetry.tools_invoked
            and first_run.active(self.config.persona_dir)
        ):
            logger.warning(
                "interview question with no card — forcing the call: %r",
                reply_text[:80],
            )
            card_msgs = messages + [
                ChatMessage(role="assistant", content=reply_text),
                ChatMessage(
                    role="user",
                    content=(
                        "[Your question is already spoken and heard. Call "
                        "choice_card NOW for that exact question, with options "
                        "composed from this conversation. Output ONLY the tool "
                        "call; no prose.]"
                    ),
                ),
            ]
            with Timer(telemetry, "tool_round_trip_ms"):
                await self._maybe_run_tools(
                    card_msgs, opts, telemetry, session, emit, persona,
                    decisions_out=turn_decisions,
                )
            if telemetry.tools_invoked:
                logger.info("forced card round delivered: %s", telemetry.tools_invoked)

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
                "text": sanitize_display_text(reply_text),
                "persona_name": persona.name,
                "model_used": result.model_used,
            },
        )

        # --- SPEAKING COMPLETE ------------------------------------------------
        await emit("speaking_complete", {"action": "speaking_complete"})
        session.state = State.IDLE
        session.record_turn(user_text, reply_text, persona.name)

        # --- TELEMETRY --------------------------------------------------------
        telemetry.sentences_spoken = sentences_spoken
        cpt = self.config.context.chars_per_token
        telemetry.completion_tokens_est = (
            result.usage.completion_tokens or estimate_tokens(reply_text, cpt)
        )
        if result.usage.prompt_tokens:
            telemetry.prompt_tokens_est = result.usage.prompt_tokens
        telemetry.emit()

    def _persona_tool_grants(self, persona: Persona) -> dict | None:
        """The persona's catalog grants (`tool_grants` in persona.json:
        {"domains": [...], "allow": [...], "deny": [...]}). Absent key -> None ->
        the full registry (backward compatible). The per-persona tool-subset
        seam: selection reliability degrades with tool-set size (measured
        2026-06-05; wiki tool-catalog.md), so each persona is granted only the
        domains it actually serves."""
        if first_run.active(self.config.persona_dir):
            # The interview and nothing else; seventeen tools and no
            # direction measured out to zero interview-tool calls.
            return dict(first_run.INTERVIEW_GRANTS)
        if self._in_brain_beat():
            # Same reasoning, one beat later. Also keeps the new persona from
            # creating ANOTHER persona while talking about memory.
            return dict(first_run.BRAIN_GRANTS)
        cfg = persona.config if isinstance(persona.config, dict) else {}
        grants = cfg.get("tool_grants")
        return grants if isinstance(grants, dict) else None

    async def _emit_brain_info(self, emit: Emit) -> None:
        """The second-brain screen's furniture: where the memory lives and
        what is in it, from disk. Emitted once when the beat opens. Best
        effort: an unconfigured root just means the screen shows no path."""
        try:
            root = hearth_engram()
        except Exception:  # noqa: BLE001 - unconfigured memory is not fatal
            return
        folders = []
        for name in ("Projects", "Areas", "Thoughts", "Resources"):
            d = root / name
            entries = 0
            if d.is_dir():
                entries = sum(1 for _ in d.iterdir())
            folders.append({"name": name, "entries": entries})
        await emit(
            "brain_info",
            {"action": "brain_info", "root": str(root), "folders": folders},
        )

    def _in_brain_beat(self) -> bool:
        """True while the second-brain beat is open.

        Two conditions, and both are load-bearing. The flag says the client
        reached the screen and asked for it; the disk check says the beat still
        has work to do. Either alone is wrong: the flag alone would keep the
        direction attached for the rest of the session after the project is
        written, and the disk check alone would re-open the beat months later
        for anyone who deleted their last project.
        """
        if not self._brain_beat:
            return False
        try:
            open_still = first_run.brain_beat_open(hearth_engram())
        except Exception:  # noqa: BLE001 - unconfigured memory ends the beat
            open_still = False
        if not open_still:
            self._brain_beat = False
        return open_still

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
        # First run overrides the persona's reasoning to OFF: the interview
        # offers two tools and no discovery chain, and thinking was costing
        # 10-17s per decision round on a turn whose whole job is one
        # choice_card. Sulivan thinks again the moment the house is his.
        think = bool(tl.get("reasoning")) and not first_run.active(self.config.persona_dir)
        decision_opts = replace(opts, enable_thinking=True) if think else opts
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

        # Thinking filler: the phrase that covers the gap while a handler runs.
        # The task is returned to run_turn; the answer consumer joins it for
        # audio order. "audio" flips the moment the filler's first PCM frame is
        # emitted. Before that it can still be called off; after it, cancelling
        # would cut a word in half.
        #
        # It starts on the FIRST HANDLER RETURN rather than on the decision that
        # carries tool_calls. A permission card has to sit in silence while it
        # waits for the operator, and starting synthesis at decision time races
        # the card: the house would narrate over a question it has not been
        # answered yet. "names" carries the decision's tools across that gap so
        # the phrase is still chosen from the whole call, not just one result.
        filler_holder: dict = {"task": None, "audio": False, "names": []}

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
            filler_holder["names"] = names

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
            # A handler that came back asking for permission has not done its
            # work yet: the card is on screen and the turn is parked on the
            # operator. Say nothing until they answer. Any other first return
            # is the cue the filler was waiting for.
            waiting = bool((getattr(result, "data", None) or {}).get("await_permission"))
            if waiting:
                task = filler_holder.get("task")
                if task is not None and not task.done() and not filler_holder["audio"]:
                    task.cancel()
                    filler_holder["task"] = None
                    logger.info("filler dropped: permission_card waiting for operator")
            elif filler_holder["task"] is None:
                phrase = registry.speak_phrase(filler_holder.get("names") or [name])
                if phrase:
                    filler_holder["task"] = asyncio.create_task(
                        self._speak(
                            phrase, session, emit, False, 0, telemetry,
                            audio_flag=filler_holder,
                        )
                    )
            # The second brain's commit, told to the client the same way the
            # persona handover is: a named message rather than a card. The
            # screen needs to know the beat closed, and "the persona stopped
            # talking" is not that -- it is also what a failed turn looks like.
            if name == "start_project" and getattr(result, "ok", False):
                data = getattr(result, "data", {}) or {}
                await emit(
                    "project_started",
                    {
                        "action": "project_started",
                        "project": data.get("project"),
                        "title": data.get("title"),
                        "created": bool(data.get("created")),
                    },
                )
            # The beat's other two exits: an imported brain or a plain
            # decline. Same contract as project_started -- the SCREEN is told
            # the beat closed, because silence is also what failure looks
            # like. An import re-emits brain_info so the chips and the path
            # follow the bridge.
            if name in ("import_brain", "complete_brain_setup") and getattr(result, "ok", False):
                data = getattr(result, "data", {}) or {}
                await emit(
                    "brain_setup_complete",
                    {
                        "action": "brain_setup_complete",
                        "imported": data.get("brain_imported"),
                    },
                )
                if name == "import_brain":
                    await self._emit_brain_info(emit)
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
                    # A card on screen has already answered, so "let me check
                    # the weather" is no longer covering a wait -- it is
                    # narrating something the operator can read. The filler
                    # covers latency; when it loses the race to the card it has
                    # nothing left to cover and is dropped.
                    #
                    # This is a race, and losing it is normal on a slow
                    # machine: the phrase is queued the instant tool_calls
                    # arrive, but synthesis took 7.6s on the 8 GB Air while the
                    # handler returned in 2.4s. A machine that synthesises
                    # faster than its tools run still speaks it, which is the
                    # behaviour worth keeping.
                    #
                    # Only before the first frame. After that it is being heard
                    # and cancelling would cut a word in half.
                    task = filler_holder.get("task")
                    if task is not None and not task.done() and not filler_holder["audio"]:
                        task.cancel()
                        filler_holder["task"] = None
                        logger.info(
                            "filler dropped: %s rendered before it could be spoken",
                            op.get("type") or op.get("op"),
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
            # Keep any tool results already appended (e.g. a successful read_file
            # before a later write_file brain 500). Inject an explicit failure so
            # the model cannot invent "I drafted a file at ...".
            fail_note = (
                "\n\n[TOOL ROUND FAILED] A later tool call could not complete "
                f"({type(exc).__name__}: {str(exc)[:240]}). "
                "Do NOT claim a file was written or saved. Do NOT invent a draft "
                "path. Say plainly that the draft could not be saved and offer to "
                "retry."
            )
            if len(msgs_dict) > original_len:
                for d in reversed(msgs_dict):
                    if d.get("role") == "tool":
                        d["content"] = str(d.get("content") or "") + fail_note
                        break
                else:
                    msgs_dict.append({"role": "user", "content": fail_note.strip()})
                tool_names = [
                    d.get("name", "") for d in msgs_dict if d.get("role") == "tool"
                ]
                telemetry.tools_invoked = [n for n in tool_names if n]
                return [
                    ChatMessage(
                        role=d.get("role", "user"),
                        content=d.get("content") or "",
                        tool_calls=d.get("tool_calls"),
                        tool_call_id=d.get("tool_call_id"),
                        name=d.get("name"),
                    )
                    for d in msgs_dict
                ], filler_holder["task"]
            return [
                *messages,
                ChatMessage(role="user", content=fail_note.strip()),
            ], filler_holder["task"]

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

    async def _structured_interview_turn(
        self,
        session: Session,
        persona: Persona,
        user_text: str,
        emit: Emit,
        telemetry: TurnTelemetry,
        ctx: dict,
    ) -> None:
        """One interview turn as structured output: a single grammar-
        constrained brain call whose JSON carries the speech, the card, and
        eventually the commit. Deterministic form, improvised content -- the
        model cannot omit the card, cannot leak it into the voice, and cannot
        double-call it, because the reply shape is enforced at the token
        level. The parsing side stays tolerant anyway (the compose_view
        discipline): a malformed field costs that field, never the turn."""
        import json as _json

        session.state = State.THINKING
        await emit(
            "thinking_message",
            {"action": "thinking_message", "persona_name": persona.name},
        )

        ctx["stage"] = "tts"
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            None,
            self.tts.sync_persona_voice,
            persona.voice_reference_audio,
            persona.voice_reference_text,
        )

        chat_structured = getattr(self.brain, "chat_structured", None)
        if chat_structured is None:
            logger.warning("brain has no chat_structured; interview falls back to the normal path")
            await self._run_turn_impl(session, persona, user_text, emit, telemetry, ctx)
            return

        ctx["stage"] = "context_assembly"
        system_prompt = persona.system_prompt
        direction = first_run.direction_text()
        if direction:
            system_prompt = system_prompt + "\n\n" + direction
        messages = self.assembler.build(
            system_prompt=system_prompt,
            memory_block="",
            history=session.history,
            user_text=user_text,
            telemetry=telemetry,
            device_context=session.device_context,
            tool_specs=[],
        )

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
            model_path=resolve_model(dm),
            enable_thinking=False,
        )

        ctx["stage"] = "brain_structured"
        with Timer(telemetry, "brain_total_ms"):
            raw = await chat_structured(messages, opts, first_run.INTERVIEW_SCHEMA, "interview_turn")

        data: dict = {}
        try:
            parsed = _json.loads(raw)
            if isinstance(parsed, dict):
                data = parsed
        except ValueError:
            logger.warning("structured interview reply did not parse: %.300r", raw)

        speech = str(data.get("speech") or "").strip()
        if not speech:
            speech = "Forgive me, I lost my words for a moment. Could you say that again?"

        # The commit first: if the persona is ready, the speech is the goodbye
        # and the card fields are noise by contract.
        commit = data.get("commit")
        committed = False
        new_persona_name = ""
        if isinstance(commit, dict) and str(commit.get("name") or "").strip():
            from ..tools.handlers.creation import create_persona as _create

            allowed = ("name", "description", "system_prompt", "temperament", "voice_design", "colour")
            result = await loop.run_in_executor(
                None, lambda: _create(**{k: commit[k] for k in allowed if k in commit})
            )
            if result.ok:
                committed = True
                new_persona_name = str((result.data or {}).get("persona_created") or "")
                telemetry.tools_invoked.append("create_persona")
                logger.info("structured interview committed: %s", commit.get("name"))
                # The handover is product copy, same as the opening: Sulivan's
                # goodbye lands the same way every install, whatever goodbye
                # the model composed.
                speech = first_run.farewell_text(str(commit.get("name")).strip())
            else:
                logger.warning("structured commit failed: %s", result.content[:160])

        await emit(
            "ai_response",
            {
                "action": "ai_response",
                "text": sanitize_display_text(speech),
                "persona_name": persona.name,
            },
        )

        card_note = ""
        question = str(data.get("question") or "").strip()
        options = data.get("options") if isinstance(data.get("options"), list) else []
        if not committed and question and options:
            from ..tools.handlers.choice import choice_card as _choice

            result = _choice(question=question, options=options)
            if result.ok and session.capabilities.get("ui_render"):
                card = result.data.get("ui_component")
                if card:
                    await emit("ui_component", {"action": "ui_component", **card})
                    telemetry.tools_invoked.append("choice_card")
                    card_note = " [The options are on a card on their screen.]"
            elif not result.ok:
                logger.warning("structured card rejected: %s", result.content[:120])

        await self.say(session, persona, speech, emit)
        session.record_turn(user_text, speech + card_note)

        if committed and new_persona_name and self.personas is not None:
            # The handover: the new persona owns the house from here. Fresh
            # history so their first words come from their own prompt, not
            # from five turns of Sulivan speaking (the subagent principle:
            # a new speaker gets a new context). The interview itself is
            # preserved in the ledger.
            try:
                switched = self.personas.switch(new_persona_name)
                session.history.clear()
                await emit(
                    "persona_switched",
                    {
                        "action": "persona_switched",
                        "persona_name": new_persona_name,
                        "status": "success",
                    },
                )
                await emit(
                    "persona_config",
                    {
                        "action": "persona_config",
                        "persona_name": new_persona_name,
                        "config": switched.public_config(),
                    },
                )
                logger.info("first-run handover: session now speaks as %s", new_persona_name)
            except Exception as exc:  # noqa: BLE001 - a failed switch must not kill the turn
                logger.warning("first-run handover failed (%s); Sulivan remains", exc)

        self.ledger.decision(
            session=session.session_id,
            persona=persona.name,
            question=user_text,
            decisions=[{"round": 1, "reasoning": "", "tools": list(telemetry.tools_invoked)}],
            tools_invoked=list(telemetry.tools_invoked),
            answer_head=speech,
        )
        logger.info(
            "structured interview turn (tools=%s): %r",
            telemetry.tools_invoked,
            speech[:160],
        )
        telemetry.emit()

    async def _salvage_text_tool_call(
        self,
        text: str,
        session: Session,
        emit: Emit,
        persona,
        telemetry: TurnTelemetry,
    ) -> bool:
        """A tool call written into the speech channel still means the tool.

        Parses the first call:name{...} out of the streamed text; when the
        turn's own registry knows the tool and the arguments parse, the call
        runs and its cards emit exactly as a proper tool round would have.
        Returns True only when a call actually executed. Never raises: a
        salvage that fails leaves the empty-answer path to do its work."""
        from ..tools import resolve_registry, tools_enabled
        from ..tools.loop import parse_tool_args

        try:
            if not tools_enabled():
                return False
            m = _TEXT_TOOL_CALL_RE.search(text)
            if m is None:
                return False
            raw = _balanced_json(text, m.end() - 1)
            if raw is None:
                return False
            args = parse_tool_args(raw)
            if not args:
                return False
            name = m.group(1)
            registry = resolve_registry(
                self._persona_tool_grants(persona), session.capabilities
            )
            if name not in registry.names():
                return False
            result = await registry.invoke(name, args)
            if not result.ok:
                logger.warning("salvaged %s ran but failed: %s", name, result.content[:120])
                return False
            telemetry.tools_invoked.append(name)
            if session.capabilities.get("ui_render"):
                from .composer import compose_for_result

                for op in compose_for_result(name, result):
                    with contextlib.suppress(Exception):
                        await emit("ui_component", {"action": "ui_component", **op})
            logger.info("salvaged text-channel tool call: %s", name)
            return True
        except Exception as exc:  # noqa: BLE001 - salvage is best-effort
            logger.warning("text tool-call salvage failed: %s", exc)
            return False

    async def _scripted_opening(self, session: Session, persona, emit: Emit) -> None:
        """The interview walkthrough: what a persona is, and the first
        question, with its card. Deterministic on purpose (2026-08-07): a
        12B asked to open freely produced a different opener every run --
        permission-asking, answering its own card, promising cards it never
        rendered. The text lands in history as the assistant turn, so the
        model picks up the conversation as if it had said it."""
        text = first_run.OPENING_TEXT
        await emit(
            "thinking_message",
            {"action": "thinking_message", "persona_name": persona.name},
        )
        await emit(
            "ai_response",
            {"action": "ai_response", "text": text, "persona_name": persona.name},
        )
        if session.capabilities.get("ui_render"):
            await emit("ui_component", {"action": "ui_component", **first_run.OPENING_CARD})
        # say() streams the TTS and closes with speaking_complete.
        await self.say(session, persona, text, emit)
        session.record_turn(
            "(I am ready to make my persona.)",
            text + " [The options are on a card on their screen; their answer comes next.]",
        )
        logger.info("first-run: scripted opening delivered")

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
            {
                "action": "tts_chunk_start",
                "seg_idx": 0,
                "sample_rate": sr,
                "text": sanitize_display_text(text),
            },
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
        audio_flag: dict | None = None,
    ) -> tuple[bool, int]:
        """Stream one sentence's TTS as PCM chunks (tts_chunk_start/binary/end)."""
        if _skip_tts_sentence(sentence):
            logger.info("skipping TTS for markup-like sentence: %r", sentence[:120])
            return speaking_started, sentences_spoken
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
                "text": sanitize_display_text(sentence),
            },
        )
        with Timer(telemetry, "tts_total_ms", accumulate=True):  # summed across sentences
            try:
                async for pcm in self.tts.stream_sentence(sentence):
                    # Once a frame is out it is being heard, and this sentence
                    # can no longer be cancelled without cutting a word in
                    # half. See the filler's cancellation in _maybe_run_tools.
                    if audio_flag is not None:
                        audio_flag["audio"] = True
                    await emit("audio", pcm)  # binary PCM frame
            except Exception as exc:  # noqa: BLE001 - surface but keep turn alive
                logger.error("TTS failed for sentence: %s", exc)
                await emit(
                    "tts_error",
                    {"action": "tts_error", "message": str(exc), "seg_idx": seg_idx},
                )
        await emit("tts_chunk_end", {"action": "tts_chunk_end", "seg_idx": seg_idx})
        return True, sentences_spoken + 1
