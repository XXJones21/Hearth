"""Receipts: the facts under the day, read rather than written.

Spec section 5. A receipt a model generated is not a receipt, so this is
Python: commits by repository from git, files touched and session counts
from the inbox's log copies. Selene writes the prose above it; this is
what a push ledger and every "what changed today" question read.
"""

from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger("valar.memory.receipts")

MAX_COMMITS = 12
MAX_FILES = 15


def _commits(engram_root: Path, day: str) -> list[str]:
    from . import dev_harvest

    lines: list[str] = []
    try:
        sources = dev_harvest.dev_sources(engram_root)
    except Exception as exc:  # noqa: BLE001
        logger.warning("receipts: dev sources unavailable (%s)", exc)
        return []
    for repo, slug in sources:
        try:
            commits, _branches, totals = dev_harvest._day_commits(repo, day)
        except Exception as exc:  # noqa: BLE001 - one bad repo never ends the pass
            logger.warning("receipts: %s failed (%s)", slug, exc)
            continue
        if not commits:
            continue
        lines.append(f"- {slug} ({totals}):")
        for c in commits[:MAX_COMMITS]:
            lines.append(f"  {c.lstrip('- ').rstrip()}")
        if len(commits) > MAX_COMMITS:
            lines.append(f"  ... {len(commits) - MAX_COMMITS} more")
    return lines


def _by_persona(engram_root: Path, day: str, personas: list[str]) -> list[str]:
    from .persona_day_report import read_inbox_log

    lines: list[str] = []
    for name in personas:
        entries = read_inbox_log(engram_root, day, name)
        if not entries:
            continue
        sessions = len({e.get("session") for e in entries})
        files: list[str] = []
        for e in entries:
            for t in e.get("touched") or []:
                parts = str(t).split(" ", 1)
                if len(parts) == 2 and parts[1] and parts[1] not in files:
                    files.append(parts[1])
        lines.append(
            f"- {name}: {sessions} session{'s' if sessions != 1 else ''}, "
            f"{len(entries)} turn{'s' if len(entries) != 1 else ''}"
        )
        for f in files[:MAX_FILES]:
            lines.append(f"  {f}")
        if len(files) > MAX_FILES:
            lines.append(f"  ... {len(files) - MAX_FILES} more")
    return lines


def render(engram_root: Path, day: str, personas: list[str]) -> str:
    """The Receipts section body, or empty when there is nothing to show."""
    commits = _commits(Path(engram_root), day)
    per = _by_persona(Path(engram_root), day, personas)
    if not commits and not per:
        return ""
    parts: list[str] = []
    if commits:
        parts.append("Commits:")
        parts.extend(commits)
    if per:
        if parts:
            parts.append("")
        parts.append("Work by persona:")
        parts.extend(per)
    return "\n".join(parts)
