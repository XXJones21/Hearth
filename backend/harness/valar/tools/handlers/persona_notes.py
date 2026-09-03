"""The persona's own pen: the one tool that writes under its memory/.

Spec section 3 of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md. Three
actions over three targets. The target file is resolved from the acting
persona, never from an argument, so there is no shape of call that writes
into another persona's tree. The harness stamps the date; the model
supplies only the words.

A write past the cap is refused with the current contents and an
instruction to prune, because the alternative is the harness silently
deciding which of the persona's memories to lose. Three refusals in one
turn is terminal: the persona finishes its reply instead of spending the
round budget on a character count.
"""

from __future__ import annotations

import logging
from datetime import date
from pathlib import Path

from ...memory import persona_archive as pa
from ...memory import persona_memory as pm
from ...memory.acting import NoActingPersona, require_acting
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.persona_notes")

MAX_REFUSALS = 3

_TARGETS = {
    "notes": (pm.NOTES_FILE, pm.NOTES_CAP, "my notes"),
    "user": (pm.USER_FILE, pm.USER_CAP, "what I know about the operator"),
}


def _fail(message: str, reason: str) -> ToolResult:
    """ToolResult.error, in both trees.

    Valinor's takes a mandatory `reason` from a closed vocabulary; Hearth's
    ToolResult has no reason field yet. One source has to run in both, and a
    TypeError here is a signature difference, not a bug.
    """
    try:
        return ToolResult.error(message, reason=reason)
    except TypeError:
        return ToolResult.error(message)


def _sentence(label: str) -> str:
    """The label starts a sentence: "my notes" -> "My notes"."""
    return label[:1].upper() + label[1:]


def _bad(msg: str) -> ToolResult:
    return _fail(msg, "bad_input")


def _day_report(root: Path, content: str, action: str) -> ToolResult:
    """target: day. One file per day, replaced wholesale. Plan 4 reads it."""
    today = date.today().isoformat()
    path = root / pm.DAY_DIRNAME / f"{today}.md"
    if action == "remove":
        if path.exists():
            path.unlink()
            return ToolResult(content=f"My day report for {today} is deleted.")
        return _fail(f"I have no day report for {today}.", "not_found")
    body = content if content.startswith("#") else f"# {today}\n\n{content}"
    if action == "add" and path.exists():
        body = path.read_text(encoding="utf-8").rstrip("\n") + "\n\n" + content
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body.rstrip("\n") + "\n", encoding="utf-8")
    return ToolResult(
        content=f"My day report for {today} is written ({len(body):,} characters).",
        data={"path": str(path), "day": today},
    )


def memory(args: dict) -> ToolResult:
    try:
        act = require_acting()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")

    action = str(args.get("action") or "").strip().lower()
    target = str(args.get("target") or "notes").strip().lower()
    content = " ".join(str(args.get("content") or "").split())

    if action not in ("add", "replace", "remove"):
        return _bad("I can only add, replace or remove a memory entry.")
    if target not in ("notes", "user", "day"):
        return _bad(
            "I can only write to my notes, what I know about the operator, "
            "or my day report."
        )
    if action != "remove" and not content:
        return _bad("There is nothing to write.")

    root = pm.scaffold(Path(act.memory_dir))

    if target == "day":
        return _day_report(root, str(args.get("content") or ""), action)

    filename, cap, label = _TARGETS[target]
    path = root / filename
    entries = pm.read_entries(path)

    if action == "remove":
        match = content.lower()
        if not match:
            return _bad("Tell me which entry to remove.")
        keep: list[str] = []
        gone: list[str] = []
        for e in entries:
            (gone if match in e.lower() else keep).append(e)
        if not gone:
            return _fail(f"Nothing in {label} matches that.", "not_found")
        pm.write_entries(path, keep, cap)
        for e in gone:
            try:
                pa.retire_note(root, target, e, e[:10])
            except Exception as exc:  # noqa: BLE001 - retiring is bookkeeping
                logger.warning("retire_note failed: %s", exc)
        return ToolResult(
            content=(
                f"Removed 1 entry from {label}."
                if len(gone) == 1
                else f"Removed {len(gone)} entries from {label}."
            ),
            data={"removed": gone},
        )

    if action == "replace":
        pm.write_entries(path, [], cap)

    try:
        entry = pm.append_entry(path, content, cap)
    except pm.CapExceeded as exc:
        act.refusals += 1
        if act.refusals >= MAX_REFUSALS:
            return _fail(
                f"{_sentence(label)} is still full and I have tried three times. "
                "Stop writing and finish the reply; I will prune it later.",
                "denied",
            )
        listing = "\n".join(f"{i + 1}. {e}" for i, e in enumerate(exc.current))
        out = _fail(
            f"{_sentence(label)} is full ({exc.cap:,} characters). Remove one entry "
            f"first with action remove, then write again. What is there now:\n{listing}",
            "denied",
        )
        out.data = {"cap": exc.cap, "entries": exc.current}
        return out

    size = len(path.read_text(encoding="utf-8"))
    return ToolResult(
        content=f"Saved to {label}: {entry} [{size:,} of {cap:,} characters]",
        data={"entry": entry, "size": size, "cap": cap},
    )
