"""Reminder tools, and the routine record.

Both write plain markdown into the operator's own tree, so both can be undone
with a text editor and neither needs a settings screen. See
``valar/memory/reminders.py`` for the file format and, more importantly, for
what "remind me" does and does not promise here.
"""

from __future__ import annotations

import logging
from datetime import datetime

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.reminders")


def _root():
    from ...memory.journal_sync import engram_root

    return engram_root()


def _when_words(when: datetime) -> str:
    now = datetime.now()
    clock = when.strftime("%I:%M %p").lstrip("0")
    if when.date() == now.date():
        return f"today at {clock}"
    if (when.date() - now.date()).days == 1:
        return f"tomorrow at {clock}"
    return when.strftime(f"%A, %B {when.day}") + f" at {clock}"


def create_reminder(args: dict) -> ToolResult:
    """args: {when: str, text: str}. Record something to be raised at a time."""
    raw_when = str((args or {}).get("when") or "").strip()
    text = str((args or {}).get("text") or (args or {}).get("what") or "").strip()
    if not text:
        return ToolResult.error("A reminder needs to say what to remind them of.")
    if not raw_when:
        return ToolResult.error("A reminder needs a time. Ask them when.")

    root = _root()
    if root is None:
        return ToolResult.error(
            "There is no second brain connected, so there is nowhere to keep a reminder."
        )

    from ...memory.reminders import add, parse_when

    when = parse_when(raw_when)
    if when is None:
        return ToolResult.error(
            f"I could not read {raw_when!r} as a time. Ask them for it plainly: "
            "a clock time, tomorrow plus a time, or a date."
        )
    if when < datetime.now():
        return ToolResult.error(
            f"{_when_words(when)} is in the past. Ask which day they meant."
        )
    if not add(root, when, text):
        return ToolResult.error("I could not write that reminder down.")

    logger.info("reminder set %s: %s", when.isoformat(timespec="minutes"), text[:60])
    return ToolResult(
        content=(
            f"Reminder set for {_when_words(when)}: {text[:120]}\n"
            "Confirm the time back to them so a misheard hour is caught now. "
            "Be honest that you will raise it in conversation when it is due, "
            "not make a sound on your own."
        ),
        data={"when": when.isoformat(timespec="minutes"), "text": text},
    )


def list_reminders(args: dict) -> ToolResult:
    """Everything still standing, soonest first."""
    root = _root()
    if root is None:
        return ToolResult.error("There is no second brain connected.")
    from ...memory.reminders import entries

    items = entries(root)
    if not items:
        return ToolResult(content="No reminders are set.", data={"reminders": []})
    now = datetime.now()
    lines = [f"Reminders: {len(items)}"]
    for e in items:
        lines.append(
            f"- {_when_words(e['when'])}: {e['text'][:100]}"
            + ("  (due)" if e["when"] <= now else "")
        )
    return ToolResult(
        content="\n".join(lines),
        data={
            "reminders": [
                {"when": e["when"].isoformat(timespec="minutes"), "text": e["text"]}
                for e in items
            ]
        },
    )


def dismiss_reminder(args: dict) -> ToolResult:
    """Tick one off once it has been dealt with."""
    needle = str((args or {}).get("text") or (args or {}).get("which") or "").strip()
    if len(needle) < 3:
        return ToolResult.error("Say which reminder, in a few words.")
    root = _root()
    if root is None:
        return ToolResult.error("There is no second brain connected.")
    from ...memory.reminders import dismiss

    hit = dismiss(root, needle)
    if hit is None:
        return ToolResult.error(
            f"Nothing matches {needle!r} exactly one reminder. List them and ask "
            "which one, rather than ticking off the wrong thing."
        )
    return ToolResult(
        content=f"Dismissed: {hit['text'][:120]}",
        data={"text": hit["text"]},
    )


def manage_routine(args: dict) -> ToolResult:
    """args: {action: list|remove, name?: str}. The standing habits record.

    Adding a routine is deliberately NOT here. A routine is a thing the house
    DOES on a clock, and every one of them is a piece of code with a loop
    behind it; letting a conversation write a new heading would produce an
    entry that describes behaviour nobody implemented. Listing and stopping
    are the two a conversation can honestly do.
    """
    action = str((args or {}).get("action") or "list").strip().lower()
    name = str((args or {}).get("name") or "").strip()
    root = _root()
    if root is None:
        return ToolResult.error("There is no second brain connected.")
    path = root / "Areas" / "routines.md"
    try:
        text = path.read_text(encoding="utf-8") if path.is_file() else ""
    except OSError as exc:
        return ToolResult.error(f"Could not read the routines record: {exc}")

    sections: list[tuple[str, int, int]] = []
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if ln.startswith("## "):
            if sections:
                s = sections[-1]
                sections[-1] = (s[0], s[1], i)
            sections.append((ln[3:].strip(), i, len(lines)))

    if action == "list" or not name:
        if not sections:
            return ToolResult(
                content="No routines are recorded, so the house is doing nothing on a clock.",
                data={"routines": []},
            )
        names = [s[0] for s in sections]
        return ToolResult(
            content="Routines: " + ", ".join(names) + ".\nDeleting one stops it.",
            data={"routines": names},
        )

    if action in ("remove", "stop", "delete"):
        hits = [s for s in sections if name.lower() in s[0].lower()]
        if len(hits) != 1:
            names = ", ".join(s[0] for s in sections) or "none"
            return ToolResult.error(
                f"{name!r} does not name exactly one routine. Recorded: {names}."
            )
        title, start, end = hits[0]
        kept = lines[:start] + lines[end:]
        try:
            path.write_text("\n".join(kept).rstrip("\n") + "\n", encoding="utf-8", newline="\n")
        except OSError as exc:
            return ToolResult.error(f"Could not update the routines record: {exc}")
        logger.info("routine removed: %s", title)
        return ToolResult(
            content=(
                f"Stopped: {title}. The section is gone from the record, which is "
                "what turns it off. It can be started again by asking."
            ),
            data={"removed": title},
        )

    return ToolResult.error("manage_routine takes action=list or action=remove.")
