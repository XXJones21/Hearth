"""The exchange: the only thing in a room that costs inference.

Spec section 3 of docs/superpowers/specs/2026-09-02-persona-rooms-design.md.
Triggered by something said, never by a clock. Every member except the
author speaks once per round, three rounds, everyone passing ends it early.

The priority lane is here rather than in llama-server, which has no slot
reservation: a semaphore of total_slots - 1, and a park between members
while an operator turn is in flight. At one slot the park is the whole
protection, and the pause is recorded so a slow room reads honestly.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re

from ..brain.provider import BrainStreamResult, ChatOptions
from ..memory import persona_block as pb
from ..memory.acting import acting
from . import store as rs

logger = logging.getLogger("valar.rooms.exchange")

MAX_ROUNDS = 3
# Two tries, then the convener decides alone. Decision 15 sends a failure
# back to the one who failed it, which is right and is also a loop:
# decision 9's rule 2 selects the owner of an open task, so an uncapped
# failure would hand the same task to the same member forever.
MAX_TASK_ATTEMPTS = 2
PASS = "(pass)"
DENIED = ("web_search", "news_headlines", "dispatch_subagent")
PARK_POLL_S = 1.0
PARK_MAX_S = 300.0
MAX_TURN_TOKENS = 700

# Soth's declared performance tags (Persona/Soth/soth.json). They are sounded
# by OmniVoice, not read. A room has no voice on it, so a tag that reaches a
# room body is a stage direction nobody asked for: four turns of the first
# live room opened with a literal [sigh]. Only these names are stripped, so
# arpabet hints like [S OW1 TH] and ordinary bracketed prose survive.
VOICE_TAGS = frozenset(
    {
        "laughter",
        "sigh",
        "confirmation-en",
        "question-en",
        "question-ah",
        "question-oh",
        "question-ei",
        "question-yi",
        "surprise-ah",
        "surprise-oh",
        "surprise-wa",
        "surprise-yo",
        "dissatisfaction-hnn",
    }
)
_TAG_RE = re.compile(r"\[([a-z-]+)\]")
_BLANKS_RE = re.compile(r"\n{3,}")


def strip_voice_tags(text: str) -> str:
    """Remove sounded tags from a written body, leaving everything else."""
    out = _TAG_RE.sub(
        lambda m: "" if m.group(1) in VOICE_TAGS else m.group(0), text or ""
    )
    return _BLANKS_RE.sub("\n\n", out).strip()

_running: set[str] = set()
_sem: asyncio.Semaphore | None = None


def _slots() -> int:
    """What the supervisor started llama-server with.

    The env rather than /props because the semaphore is built once at import
    and /props is a network call; the two agree, since the supervisor sets
    both. If they ever diverge, /props wins and this is the place to change.
    """
    try:
        return max(1, int(os.environ.get("HEARTH_LLAMA_PARALLEL", "1") or 1))
    except ValueError:
        return 1


def _semaphore() -> asyncio.Semaphore:
    """total_slots - 1, so one slot is always free for the operator."""
    global _sem
    if _sem is None:
        _sem = asyncio.Semaphore(max(1, _slots() - 1))
    return _sem


async def _park_for_operator() -> float:
    """Wait while the operator is mid-turn. Returns the seconds parked."""
    from ..gateway.voice_loop import foreground_turns

    waited = 0.0
    while foreground_turns() > 0 and waited < PARK_MAX_S:
        await asyncio.sleep(PARK_POLL_S)
        waited += PARK_POLL_S
    return waited


def tail_turns(slot_ctx: int | None) -> int:
    """How many turns of transcript a room turn sees.

    The same three bands as persona_block.caps_for, for the same reason: a
    turn has to be correct in the context ONE SLOT gives it, which is
    16,384 at four slots. The spec names twelve and six; the tightest band
    gets four by the same shape. Older turns are not lost, they are
    read_room away.
    """
    if slot_ctx is None or slot_ctx >= 49152:
        return 12
    if slot_ctx >= 12288:
        return 6
    return 4


def _context(room: dict, transcript: list[dict], tasks: list[dict]) -> str:
    lines = [
        f"# The room: #{room['slug']}",
        f"Goal: {room['goal']}",
        "Members: " + ", ".join(room["members"]),
    ]
    if room.get("state") == "forming":
        proposed = room.get("proposed") or []
        lines.append("")
        lines.append(
            "This room is FORMING. The charter is not settled. Proposed "
            "deliverables:"
        )
        lines += [f"- {d['owner']}: {d['text']}" for d in proposed] or [
            "- none yet"
        ]
        lines.append(
            "Amend it once with amend_charter if it is wrong or incomplete, "
            "or accept it by adding nothing. Work starts after this round."
        )
    open_tasks = [t for t in tasks if t.get("status") not in rs.TERMINAL]
    if open_tasks:
        lines.append("Open tasks:")
        lines += [f"- {t['id']} {t['assignee']}: {t['text']}" for t in open_tasks]
    if room.get("state") == "awaiting_close":
        lines.append(
            f"Every task is finished. {room.get('convener', 'The convener')} "
            "should now call close_room with a summary of what came of it. "
            "That is the only thing left to do here."
        )
    lines.append("")
    lines.append("# What has been said, most recent last")
    for rec in transcript:
        lines.append(f"{rec['author']}: {rec['body']}")
    lines.append("")
    lines.append(
        "This is the tail of the room, not all of it. Call read_room for "
        "anything older."
    )

    # The operator's latest instruction goes LAST, after the room's own state
    # lines. Told to open a room while the context also said "every task is
    # finished", all three members obeyed the state line and closed ranks
    # instead. Both instructions were in the context; the stale one won on
    # position. The operator sets what a room does, so it reads last.
    latest = next(
        (
            r
            for r in reversed(transcript)
            if (r.get("meta") or {}).get("operator")
        ),
        None,
    )
    if latest:
        lines.append("")
        lines.append(
            f"# The operator said this, and it outranks anything above:\n"
            f"{latest['body']}"
        )
    return "\n".join(lines)


_DIRECTION = (
    "You are in a room with the others named above. This is a written "
    "surface: nobody hears it, so do not use performance tags. Say one "
    "short thing that moves the goal forward: an answer, a question, a "
    "task worth assigning.\n\n"
    "If you are going to DO something, call assign_task, naming yourself "
    "or another member. Saying you will do a thing is not doing it and "
    "leaves no record that it was ever owed. Talk belongs in the room; "
    "work belongs in the task list.\n\n"
    "Do not repeat what is already said. Your reply is your say, so do "
    "not call say into this room. If you have nothing to add, reply with "
    f"exactly {PASS} and nothing else."
)


async def speak(slug: str, room: dict, name: str) -> tuple[str, list[str]]:
    """One member's turn, as itself.

    Returns the reply and the tools it actually called. An empty reply
    means it said nothing. The tool list is the turn's receipt: the first
    live room had a member announce an audit and deliver a technical
    breakdown with touched == [] on every one of its ten turns, and
    nothing on the surface showed it.
    """
    from ..agents.subagent import _runtime, _to_chat_messages

    brain = _runtime.get("brain")
    personas = _runtime.get("personas")
    config = _runtime.get("config")
    if brain is None or personas is None or config is None:
        return "", []
    persona = personas.load(name)

    caps = pb.caps_for(pb.slot_context())
    operator = getattr(config, "operator_name", "") or "the operator"
    block = pb.render_block(persona.memory_dir, caps, operator)

    dm = persona.config.get("deep_model") if isinstance(persona.config, dict) else {}
    dm = dm if isinstance(dm, dict) else {}
    bc = config.brain
    opts = ChatOptions(
        max_tokens=MAX_TURN_TOKENS,
        temperature=float(dm.get("temperature", bc.temperature)),
        top_p=float(dm.get("top_p", bc.top_p)),
        top_k=int(dm.get("top_k", bc.top_k)),
        model=bc.model,
        persona_name=persona.name,
        model_path=dm.get("path", ""),
    )

    system = f"{persona.system_prompt}\n\n{block}\n\n{_DIRECTION}"
    user = _context(
        room, rs.read(slug, tail_turns(pb.slot_context())), rs.tasks(slug)
    )
    msgs: list[dict] = [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]

    from ..tools import resolve_registry, tools_enabled
    from ..tools.loop import ToolCallingLoop

    chat_tools = getattr(brain, "chat_tools", None)
    text = ""
    # The acting persona is THIS member, and its memory_dir is its OWN tree,
    # never the room's: a memory tool called during a room turn writes to the
    # persona that spoke. The room is the topic, not the owner. It wraps both
    # the tool loop and the stream, because a handler runs in either.
    with acting(
        persona.name,
        persona.memory_dir,
        session=f"room:{slug}",
        origin=f"room/{slug}",
    ):
        # Its normal grant plus the room verbs, minus web and minus dispatch.
        if tools_enabled() and chat_tools is not None:
            cfg = persona.config if isinstance(persona.config, dict) else {}
            grants = dict(cfg.get("tool_grants") or {})
            grants["deny"] = list(grants.get("deny") or []) + list(DENIED)
            grants["domains"] = list(grants.get("domains") or []) + ["rooms"]
            registry = resolve_registry(grants, None)
            if registry.names():

                async def brain_tool_call(m: list[dict], tools: list[dict]) -> dict:
                    r = await chat_tools(_to_chat_messages(m), opts, tools)
                    return {
                        "content": (r or {}).get("content") or "",
                        "tool_calls": (r or {}).get("tool_calls") or [],
                    }

                try:
                    msgs = await ToolCallingLoop(registry).run(msgs, brain_tool_call)
                except Exception as exc:  # noqa: BLE001 - a member still speaks
                    logger.warning("room %s: %s tool loop failed: %s", slug, name, exc)

        result = BrainStreamResult()
        parts: list[str] = []
        async for delta in brain.chat(_to_chat_messages(msgs), opts, result):
            parts.append(delta)
        text = strip_voice_tags("".join(parts))

    # The receipt. A tool result carries the name of the tool that produced
    # it, so the messages the loop appended are the record of what this turn
    # actually did.
    used = [str(d.get("name") or "") for d in msgs if d.get("role") == "tool"]
    used = [t for t in used if t]

    # What it was answering, which is the turn in front of it and NOT the room
    # goal. Every record in the first live room logged the goal, so no memory
    # row could say what a member had actually been asked.
    prior = rs.read(slug, 1)
    answering = (prior[-1].get("body") if prior else "") or room["goal"]

    # A room turn is this persona's own activity, so its day report and the
    # review's receipts count it with no new bookkeeping (spec section 3).
    try:
        from ..memory import persona_memory as pm

        pm.append_log(
            persona.memory_dir,
            {
                "session": f"room:{slug}",
                "origin": f"room/{slug}",
                "client": "",
                "question": pm.head(f"#{slug}: {answering}"),
                "tools": used,
                "touched": used,
                "answer": pm.head(text),
                "dispatches": [],
            },
        )
    except Exception as exc:  # noqa: BLE001 - recording never costs a turn
        logger.warning("room %s: %s turn not recorded: %s", slug, name, exc)
    return text, used


def next_speakers(
    room: dict,
    transcript: list[dict],
    tasks: list[dict],
    author: str,
    spoken: set[str],
) -> list[str]:
    """Who may speak next in this round, best first. Decision 9.

    Three rules, first match wins: a member named in the previous turn, then
    the owner of the oldest open task, then anyone who has not spoken this
    round in member order. The third rule is the old behaviour, which was the
    ONLY behaviour: the first live room asked Selene to audit the records and
    Soth answered, twice, because a fixed list order does not know it was
    addressed.

    An exact word match on a name will occasionally fire on a name used in
    passing. That is a smaller error than ignoring the address entirely, and
    it self-corrects on the next turn.
    """
    eligible = [m for m in room["members"] if m != author and m not in spoken]
    if not eligible:
        return []
    ordered: list[str] = []

    prev = transcript[-1] if transcript else None
    if prev:
        body = (prev.get("body") or "").lower()
        for m in eligible:
            if m == prev.get("author"):
                continue
            if re.search(rf"\b{re.escape(m.lower())}\b", body):
                ordered.append(m)

    for t in tasks:
        who = t.get("assignee")
        if t.get("status") == "open" and who in eligible and who not in ordered:
            ordered.append(who)

    ordered += [m for m in eligible if m not in ordered]
    return ordered


async def _closing_turn(slug: str, room: dict) -> None:
    """One turn for the convener when every task is finished.

    Not a round: the others have nothing left to say and saying it costs
    three brain calls. The convener has the summary and is the only persona
    close_room accepts, so it is the only one worth waking.
    """
    convener = room.get("convener") or ""
    if not convener:
        return
    async with _semaphore():
        try:
            text, used = await speak(slug, room, convener)
        except Exception as exc:  # noqa: BLE001 - a stuck room is worse
            logger.warning("room %s: closing turn failed: %s", slug, exc)
            return
    if text and text.strip() != PASS:
        rs.post(
            slug,
            convener,
            "message",
            text,
            meta={"round": 0, "touched": used, "closing": True},
        )


async def run_exchange(slug: str, author: str) -> int:
    """Every member except the author, once per round, up to MAX_ROUNDS.

    Order within a round comes from next_speakers and is recomputed after
    every turn, because the previous body is what carries an address.
    """
    spoken_count = 0

    # The charter round. Exactly one, and the flip to open is automatic, so a
    # room cannot stall in forming by argument. Members all passing opens the
    # room on the convener's proposal unchanged: silence is assent, and the
    # operator can amend afterwards. Decision 8.
    room = rs.load(slug)
    if room is not None and room.get("state") == "forming":
        for name in [m for m in room["members"] if m != author]:
            async with _semaphore():
                try:
                    text, used = await speak(slug, room, name)
                except Exception as exc:  # noqa: BLE001 - a failed turn passes
                    logger.warning(
                        "room %s: %s charter turn failed: %s", slug, name, exc
                    )
                    text, used = "", []
            if text and text.strip() != PASS:
                rs.post(
                    slug, name, "message", text, meta={"round": 0, "touched": used}
                )
                spoken_count += 1
        room = rs.load(slug) or room
        rs.freeze_charter(slug, list(room.get("proposed") or []))

    for rnd in range(1, MAX_ROUNDS + 1):
        room = rs.load(slug)
        if room is None or room.get("state") == "settled":
            break
        if room.get("state") == "awaiting_close":
            # Every task is finished, so a full exchange is three personas
            # agreeing the room is over: nine turns of it, measured, against
            # this design's rule that a room at rest costs nothing.
            #
            # But it cannot be silence either. A persona only speaks inside an
            # exchange, so cutting the exchange entirely left the convener
            # with no turn in which to call close_room, and the room stuck in
            # awaiting_close forever. Found immediately, 2026-09-03.
            #
            # So: the convener alone, once. It has the summary and the
            # authority; nobody else has anything to add.
            await _closing_turn(slug, room)
            break
        total = len([m for m in room["members"] if m != author])
        if not total:
            break
        spoken: set[str] = set()
        passes = 0
        while True:
            order = next_speakers(
                room, rs.read(slug, 1), rs.tasks(slug), author, spoken
            )
            if not order:
                break
            name = order[0]
            spoken.add(name)
            parked = await _park_for_operator()
            if parked:
                rs.post(
                    slug,
                    "house",
                    "message",
                    f"Paused {int(parked)}s while the operator was speaking.",
                    meta={"round": rnd},
                )
            async with _semaphore():
                try:
                    text, used = await speak(slug, room, name)
                except Exception as exc:  # noqa: BLE001 - a failed turn is a pass
                    logger.warning("room %s: %s turn failed: %s", slug, name, exc)
                    text, used = "", []
            if not text or text.strip() == PASS:
                passes += 1
                continue
            rs.post(
                slug, name, "message", text, meta={"round": rnd, "touched": used}
            )
            spoken_count += 1
        if passes == total:
            break
    logger.info("room %s: exchange spoke %d turn(s)", slug, spoken_count)
    return spoken_count


def dispatch_task(slug: str, task: dict, goal: str) -> bool:
    """Run one task's worker off the speaking loop.

    Returns False if it could not be scheduled, which the caller must report
    rather than swallow.

    assign_task used to await the worker inside the caller's tool loop, so
    the room went silent for as long as the work took. Dispatching it is what
    finally uses the slots the priority lane reserves: the semaphore covers
    speaking turns AND workers, so a room that is talking and working at once
    still leaves the operator a slot.

    A failure goes back to the convener and to whoever failed it, capped at
    MAX_TASK_ATTEMPTS. Decision 15.
    """

    async def _go() -> None:
        from ..agents.subagent import run_persona_subagent

        who = task["assignee"]
        try:
            async with _semaphore():
                result = await run_persona_subagent(
                    who,
                    f"You have been assigned this in the room #{slug}, whose "
                    f"goal is: {goal}\n\nYour task: {task['text']}\n\nDo it "
                    "and report what you did, plainly, in your own words.",
                    origin=f"room/{slug}",
                )
            body = str((result or {}).get("content") or "").strip()
            ok = bool((result or {}).get("ok")) and bool(body)
            why = str((result or {}).get("error") or "") or "it returned nothing"
        except Exception as exc:  # noqa: BLE001 - a failed worker is a fact
            body, ok, why = "", False, str(exc)

        if ok:
            rs.set_task(slug, task["id"], status="done")
            rs.post(
                slug, who, "task_done", body, meta={"task": task["id"], "ok": True}
            )
            rs.milestone(
                slug, who, "task_done", f"{who} finished {task['id']} in #{slug}"
            )
            rs.refresh_state(slug)
            trigger(slug, who)
            return

        # A failure goes to the convener AND to whoever failed it. Decision
        # 15. The convener owns the charter and can reassign or drop the
        # deliverable; the assignee is the only one holding the context of
        # what it tried. Sending it to one of them throws away half of what
        # is needed to resolve it.
        attempts = int(task.get("attempts") or 0) + 1
        room = rs.load(slug) or {}
        convener = room.get("convener") or ""
        # Back to open with its owner unchanged, not failed: the room can see
        # it, and decision 9's rule 2 selects the owner off an open task.
        rs.set_task(slug, task["id"], status="open", attempts=attempts)

        detail = f"partial result: {body}" if body else "it produced nothing"
        if attempts < MAX_TASK_ATTEMPTS:
            # Naming the convener is what makes rule 1 select them first, and
            # the reopened task is what makes rule 2 select the assignee
            # second. Convener, then the one who failed, with no special case.
            rs.post(
                slug,
                who,
                "task_done",
                f"{convener}: I could not finish {task['id']} "
                f"({task['text']}). What went wrong: {why}. What I have: "
                f"{detail}. I still hold the context, so I can take another "
                "pass, or you can reassign it.",
                meta={"task": task["id"], "ok": False, "attempts": attempts},
            )
            rs.refresh_state(slug)
            # As house, so NOBODY is excluded. Passing the assignee here
            # silenced the one persona able to act on the failure.
            trigger(slug, "house")
        else:
            rs.post(
                slug,
                who,
                "task_done",
                f"{convener}: {task['id']} has now failed {attempts} times. "
                f"Last error: {why}. I am not taking it again; it needs "
                "reassigning, rewriting, or dropping from the charter.",
                meta={"task": task["id"], "ok": False, "attempts": attempts},
            )
            rs.refresh_state(slug)
            # As the assignee, which EXCLUDES them: the cap exists so a
            # failing task stops returning to the same owner forever, which
            # is the loop decision 9 would otherwise create.
            trigger(slug, who)

    try:
        asyncio.get_running_loop().create_task(_go())
        return True
    except RuntimeError:
        logger.warning(
            "room %s: no running loop, task %s NOT dispatched", slug, task["id"]
        )
        return False


def trigger(slug: str, author: str) -> None:
    """Fire and forget. One exchange per room at a time; never raises."""
    if slug in _running:
        return
    _running.add(slug)

    async def _go() -> None:
        try:
            await run_exchange(slug, author)
        except Exception as exc:  # noqa: BLE001 - an exchange never breaks a turn
            logger.warning("room %s: exchange failed: %s", slug, exc)
        finally:
            _running.discard(slug)

    try:
        asyncio.get_running_loop().create_task(_go())
    except RuntimeError:
        _running.discard(slug)
        # Loud, not debug: this means nobody in the room will ever answer,
        # and a silent debug line hid exactly that on the first live room.
        logger.warning(
            "room %s: no running loop, exchange NOT started. The caller must "
            "be an async handler.", slug,
        )
