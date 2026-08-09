"""Routines: the house's standing habits, as plain text in the brain.

A routine is a habit or a clock job the house keeps without being asked: an
assigned persona, a trigger, and a behavior, recorded where the person can
read, edit, or delete it. The record lives in Areas because a routine is a
thing that never ends, which is exactly what that folder holds; no fifth
top-level folder, no database, no state the person cannot open in a text
editor.

The record is also the switch. The clock honors what is written here: delete
the Daily review section and the review stops running, no settings screen
required. That is the same contract screen 14 makes about the rest of the
brain, applied to behavior.

The first routine is written at the end of beat three (start_project) and
explained aloud by the new persona: each day Selene reviews what was talked
about and updates the second brain with the work that was done.
"""

from __future__ import annotations

import logging
from datetime import date
from pathlib import Path

logger = logging.getLogger("valar.memory.routines")

ROUTINES_REL = "Areas/routines.md"

FIRST_ROUTINE_TITLE = "Daily review"

_FIRST_ROUTINE_BODY = """# Routines

Standing habits of the house. Plain text: edit a routine to change it,
delete its section to stop it, and the house follows what is written here.

## {title}

- **Assigned:** Selene
- **Trigger:** daily
- **Behavior:** Review the day's conversations in Thoughts, write the
  day's review, and update each project with the work that was done.

_Started {started}._
"""


def routines_path(root: Path) -> Path:
    return Path(root) / ROUTINES_REL


def ensure_first_routine(root: Path) -> bool:
    """Write the routines file with the Daily review in it, once.

    True only when this call created the file. An existing file is left
    exactly as the person has it: their edits outrank our template.
    """
    path = routines_path(root)
    if path.exists():
        return False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            _FIRST_ROUTINE_BODY.format(
                title=FIRST_ROUTINE_TITLE, started=date.today().isoformat()
            ),
            encoding="utf-8",
        )
    except OSError as exc:
        logger.warning("routines: could not write %s (%s)", path, exc)
        return False
    logger.info("routines: first routine recorded at %s", ROUTINES_REL)
    return True


def daily_review_enabled(root: Path) -> bool:
    """Whether the Daily review section still stands in the record."""
    try:
        text = routines_path(root).read_text(encoding="utf-8")
    except OSError:
        return False
    return FIRST_ROUTINE_TITLE.lower() in text.lower()
