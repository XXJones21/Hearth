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
to the brain seam and must land behind ``VALAR_TOOLS_ENABLED`` with the voice path
defaulting to today's tool-free behavior. Until then this module documents the
contract and offers ``maybe_run_tools`` as the seam a future gateway change calls.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from . import ToolRegistry, tools_enabled
from .salvage import salvage_calls

logger = logging.getLogger("valar.tools.loop")

# Cap tool round-trips per turn so a model that loops on tool calls cannot stall a
# voice turn. The reactive design is ONE round-trip; allow a small margin.
# Persona-overridable since 2026-07-31 (tool_loop.max_rounds): the discovery
# chain (consult -> list_cards -> forge_card) needs 3+, and the fixed cap of 2
# was the structural blocker in the live 12:01 turn.
MAX_TOOL_ROUNDS = 2

# How many characters of tool RESULT one BATCH may pull in, across all its
# rounds, before further reads are deferred and the batch ends for folding.
# Only bulk readers are capped: a list_dir or an mkdir is small and must
# always run.
#
# This was a per-ROUND budget of 32k until the live logs showed the premise
# was wrong. The model stops emitting tool calls after ONE of its four
# rounds, so a per-round cap and a per-batch cap are the same thing in
# practice, and 32k left ~44k tokens of a 65,536 window unused on every
# batch while the sweep crawled at three files a batch (2026-08-16
# `5398ed8c`: 7 files in 90s). Spanning the batch makes the cap honest when
# the model DOES use several rounds, and 100k is what the window can carry:
# base ~10k tokens + 112k chars (the cap plus one 12k overshoot) is ~38k,
# leaving ~27k of headroom.
BATCH_READ_CHARS = 100_000
_BULK_READ_TOOLS = frozenset({"read_file", "search_files", "fetch_url"})

# How many of ONE round's tool calls may run at once. The loop ran every call
# serially until 2026-08-28, which is invisible for a local read and decisive
# for a dispatch: an agent emitting five `dispatch_subagent` calls waited for
# each worker in turn, so an agent-authored fan-out was always 1-wide while the
# same fan-out written in Python was 5-wide. That made every measured
# comparison between the two a comparison of the harness against itself.
#
# 5 is the operator's ceiling, chosen for headroom rather than throughput: the
# orchestrator persona and the speaking subagent are also live, so a full round
# plus those is 7 agents against one resident model. Bulk readers are excluded
# from parallel rounds entirely, since their character budget is accumulated
# sequentially and a local read gains nothing from overlap.
PARALLEL_TOOL_CALLS = 5

# The two halves of a failed tool result. The handler's message is the only
# place a next tool may be named; this note is the harness speaking, and it
# names NO tool on purpose.
#
# It used to end "If a path is missing, call mkdir or pick a file inside the
# folder." voice_loop's recoverable-miss detector searches the tool message
# for a named next tool, and it had no way to tell the handler's words from
# these, so it matched "call mkdir" in the harness's OWN note on EVERY
# failure. Live 2026-08-27 `07603a9d`: four web_search misses against
# DuckDuckGo, which name no tool and cannot be recovered, were each
# classified recoverable and bought a free extra brain call, and the model
# was advised to consider creating a folder after a restaurant lookup came
# back empty.
#
# Keep this note tool-agnostic. When a specific tool IS the right next step,
# say so in the handler; files.py list_dir and read_file already do.
TOOL_ERROR_PREFIX = "[tool error] "
TOOL_ERROR_NOTE = (
    "\n[This call did not succeed. Do not present the text above as if it "
    "were the answer. If the message above names another tool to call, call "
    "that tool now. Do not give up. Do not invent contents.]"
)


class ToolCallingLoop:
    """Runs the tool round-trip against a tool-aware brain call.

    ``brain_tool_call`` is an injected async callable:
        await brain_tool_call(messages, tools) -> {content, tool_calls}
    where ``tool_calls`` is the OpenAI shape
    ``[{id, function: {name, arguments(json str)}}]``. Injecting it keeps this
    module decoupled from the streaming voice path and unit-testable with a fake.
    """

    def __init__(self, registry: ToolRegistry, max_rounds: int = MAX_TOOL_ROUNDS, ledger=None):
        self.registry = registry
        self.max_rounds = max(1, int(max_rounds))
        self.ledger = ledger
        # Decision records for the turn: one {round, reasoning, tools} per
        # brain response that carried tool calls (SCX v2 / ledger exhaust).
        self.decisions: list[dict[str, Any]] = []

    async def _prefetch(self, fresh_calls: list) -> dict[int, Any]:
        """Run one round's independent tool calls at once, keyed by position.

        Returns {} when the round is not eligible, in which case the caller
        invokes each tool in place and behaviour is byte-for-byte what it was.
        Eligibility is narrow on purpose:

        - more than one call, since one call has nothing to overlap with;
        - no bulk reader in the round, because their character budget
          accumulates across the round's results and a deferral decision made
          from a partial total is not the same decision. Reads are local and
          fast, so nothing is lost by leaving that path alone.

        Results are keyed by INDEX rather than tool_call id: ids come from the
        model and are neither guaranteed present nor unique. Ordering of the
        message list is unaffected, since the caller still walks fresh_calls in
        order and appends each result where it always went. Permission resume
        stays in the caller too, so a round that trips several permission
        prompts still raises them one at a time.
        """
        if len(fresh_calls) < 2:
            return {}
        names = [(c.get("function") or {}).get("name", "") for c in fresh_calls]
        if any(n in _BULK_READ_TOOLS for n in names):
            return {}

        sem = asyncio.Semaphore(PARALLEL_TOOL_CALLS)

        async def one(idx: int, call: dict) -> tuple[int, Any]:
            fn = call.get("function", {})
            raw = fn.get("arguments") or "{}"
            try:
                args = json.loads(raw) if isinstance(raw, str) else dict(raw)
            except Exception:  # noqa: BLE001 - the caller re-parses and handles it
                return idx, None
            async with sem:
                return idx, await self.registry.invoke(fn.get("name", ""), args)

        logger.info("running %d tool calls concurrently (cap %d): %s",
                    len(fresh_calls), PARALLEL_TOOL_CALLS, names)
        out: dict[int, Any] = {}
        for idx, res in await asyncio.gather(
            *(one(i, c) for i, c in enumerate(fresh_calls))
        ):
            if res is not None:
                out[idx] = res
        return out

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
        coming — the loop stops and appends a speech-only instruction to the last
        tool result (template-safe: tool content, not a trailing system message)
        so the final streaming call produces prose. That closer must not say the
        job is done; leftover file work is session.open_task (2026-08-16)."""
        if not self.registry.names():
            return messages
        # Schemas are built PER ROUND, not once. A tool withdrawn in round 2
        # has to be gone from round 3's offer, and from every later batch in
        # the same turn. maybe_run_tools builds a fresh loop per batch, so the
        # ledger is the only thing that carries withdrawal across them.
        seen_calls: set[tuple[str, str]] = set()
        force_answer = False
        batch_chars = 0
        for round_idx in range(self.max_rounds):
            withdrawn = self.ledger.withdrawn() if self.ledger is not None else set()
            tools = self.registry.schemas(exclude=withdrawn)
            response = await brain_tool_call(messages, tools)
            tool_calls = (response or {}).get("tool_calls") or []

            # A call the model WROTE instead of made. Only when the round
            # carried none of its own, so a real call always wins, and only
            # for a tool in `tools`, which is this caller's own grant. See
            # valar/tools/salvage.py for what it refuses and why.
            if not tool_calls:
                salvaged, cleaned = salvage_calls(
                    str((response or {}).get("content") or ""), tools
                )
                if salvaged:
                    tool_calls = salvaged
                    response = dict(response or {})
                    response["content"] = cleaned
                    response["tool_calls"] = salvaged

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
            prefetched = await self._prefetch(fresh_calls)
            for call_idx, call in enumerate(fresh_calls):
                fn = call.get("function", {})
                name = fn.get("name", "")
                raw_args = fn.get("arguments") or "{}"
                try:
                    args = json.loads(raw_args) if isinstance(raw_args, str) else dict(raw_args)
                except Exception:  # noqa: BLE001
                    args = {}
                # Reading budget. The fold that keeps the window flat runs
                # BETWEEN batches, so a single round that reads the whole
                # remaining tree blows the context before any fold can help:
                # live 2026-08-16 `cbf30b9f` asked for 30 read_file calls in
                # one round and took a 400 at 97,509 tokens. Over budget, the
                # rest of the round is DEFERRED rather than executed. Each
                # deferred call still gets a result so tool_call pairing
                # holds, and the file stays unread in the open-task remainder,
                # so the next round picks it up.
                if name in _BULK_READ_TOOLS and batch_chars >= BATCH_READ_CHARS:
                    # Un-see it. The duplicate guard keys on (name, args) and
                    # was stamped when the round was assembled, so leaving it
                    # there would make the retry look like a repeat and drop
                    # the file for good.
                    seen_calls.discard((name, str(fn.get("arguments") or "")))
                    logger.info("deferring %s: batch reading budget spent", name)
                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": call.get("id", ""),
                            "name": name,
                            "content": (
                                "[deferred] Not read yet: this batch of "
                                "reading is full. The file is still on the "
                                "list and nothing is lost. Keep going: ask "
                                "for it again and it will be read."
                            ),
                        }
                    )
                    continue
                result = prefetched.get(call_idx)
                if result is None:
                    result = await self.registry.invoke(name, args)
                if self.ledger is not None:
                    self.ledger.record(
                        name, bool(result.ok), getattr(result, "reason", ""), args
                    )
                if on_tool_result is not None:
                    try:
                        await on_tool_result(name, result)
                    except Exception as exc:  # noqa: BLE001 - emits never break tools
                        logger.warning("on_tool_result callback failed: %s", exc)
                if (result.data or {}).get("await_permission"):
                    result = await _resume_after_permission(self.registry, name, args, result)
                    if result.ok and on_tool_result is not None:
                        try:
                            await on_tool_result(name, result)
                        except Exception as exc:  # noqa: BLE001
                            logger.warning("on_tool_result callback failed: %s", exc)
                # Phase 1c: a failed tool must be structurally legible. Before
                # this, ok=False was dropped here and the model read the error
                # string as if it were data (and could present it as an answer).
                # The marker + instruction make failure unmistakable while the
                # turn still survives (the existing recovery contract).
                content = result.content
                if not result.ok:
                    # Live 2026-08-16: "is a directory, call list_dir" was
                    # wrapped as "you could not do it / answer from what you
                    # know" and the 12B gave up mid-ingest. Recoverable misses
                    # must stay retries. Permanent failures still say so in
                    # the handler text; this wrapper must not override that
                    # with a stop.
                    content = (
                        TOOL_ERROR_PREFIX
                        + (content or "unknown error")
                        + TOOL_ERROR_NOTE
                    )
                batch_chars += len(content or "")
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call.get("id", ""),
                        "name": name,
                        "content": content,
                    }
                )
                if self.ledger is not None and name in self.ledger.withdrawn():
                    # Name the tool and the shape of the gap, so the model has
                    # something specific to say. The last clause is the same
                    # turn shape that produced "I shall attempt to locate those
                    # breakfast options for you momentarily"; the deferral
                    # guard catches it if the model tries anyway.
                    messages[-1]["content"] = str(messages[-1]["content"]) + (
                        f"\n[{name} cannot answer this. It was tried and failed "
                        "the same way twice. Do not call it again this turn. "
                        "Tell the operator plainly that you cannot look this "
                        "up, name what you cannot do, and do not promise to "
                        "try later.]"
                    )
            if batch_chars >= BATCH_READ_CHARS:
                # Spent. Another round here could only defer, burning a
                # decision call for nothing. End the batch so the caller
                # folds and starts a fresh one.
                logger.info(
                    "batch reading budget spent (%d chars) after round %d",
                    batch_chars, round_idx + 1,
                )
                break
            if round_idx == self.max_rounds - 1:
                force_answer = True
        if force_answer and messages and messages[-1].get("role") == "tool":
            # Speech has tools off. This closer must keep XML out of TTS
            # without telling the model the JOB is done (live 2026-08-16:
            # "Do not call any more tools" ended a 39-file wiki ingest
            # after four reads). Unfinished file work is session.open_task.
            messages[-1]["content"] = (
                str(messages[-1].get("content") or "")
                + "\n\n[This spoken answer cannot emit tools. Speak plain "
                "language from the results above. If unread files remain, "
                "say so in one sentence; do not claim the job is finished.]"
            )
        return messages


async def _resume_after_permission(registry, name: str, args: dict, pending) -> Any:
    """Hold the turn on a permission card, then retry the same call if granted."""
    from .handlers.files import decision_error, wait_for_decision
    from .spec import ToolResult

    request_id = str((pending.data or {}).get("request_id") or "")
    logger.info("tool loop waiting on permission id=%s tool=%s", request_id, name)
    decision = await wait_for_decision(request_id)
    if decision == "granted":
        logger.info("permission granted; retrying %s", name)
        return await registry.invoke(name, args)
    if decision == "failed":
        # They approved and it still could not be done. Report what actually
        # happened; a model told "denied" here blames a permission problem
        # that the operator just solved.
        detail = decision_error(request_id) or "The folder could not be opened."
        return ToolResult(
            content=(
                f"Access was approved, but it could not be used: {detail} "
                "This is NOT a permission problem. Say what actually went wrong "
                "and do not invent file contents."
            ),
            ok=False,
            reason="internal",
        )
    if decision == "denied":
        message = "The operator denied access to that folder."
        failure = "denied"
    else:
        message = "The permission request timed out before anyone approved it."
        failure = "timeout"
    return ToolResult(
        content=message + " Do not invent file contents.",
        ok=False,
        reason=failure,
    )


async def maybe_run_tools(
    messages: list[dict[str, Any]],
    brain_tool_call,
    registry: ToolRegistry | None = None,
    on_tool_calls=None,
    on_tool_result=None,
    max_rounds: int = MAX_TOOL_ROUNDS,
    decisions_out: list | None = None,
    ledger=None,
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
    loop = ToolCallingLoop(reg, max_rounds=max_rounds, ledger=ledger)
    try:
        # The rounds that DID run are the evidence for why a turn failed, so
        # they must reach the ledger even when a later round raises. Live
        # 2026-08-16 `939d446c`: a context-overflow 400 lost 19 executed tool
        # calls from the decision record while telemetry still counted them.
        return await loop.run(messages, brain_tool_call, on_tool_calls, on_tool_result)
    finally:
        if decisions_out is not None:
            decisions_out.extend(loop.decisions)
