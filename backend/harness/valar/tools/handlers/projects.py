"""Project tools: what the second brain is holding, and adding to it.

``start_project`` could create one and nothing could list them, which made
the brain a place things went into and never came back out of by name. These
are the other two directions.

Both work on ``$ENGRAM/Projects/<name>/claude.md``, the file every other part
of the memory layer already writes: the daily review appends decisions there
on its own schedule, and this is the same append a conversation can ask for
on purpose.
"""

from __future__ import annotations

import logging
import re
from datetime import date
from pathlib import Path

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.projects")

_MAX_NOTE_CHARS = 1_000
_LIST_CAP = 60


def _engram_root() -> Path | None:
    from ...memory.journal_sync import engram_root

    return engram_root()


def _projects_dir() -> Path | None:
    root = _engram_root()
    if root is None:
        return None
    p = root / "Projects"
    return p if p.is_dir() else None


def _title_of(claude_md: Path) -> str:
    """The project's own first heading, which is what the operator called it."""
    try:
        for line in claude_md.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("# "):
                return line[2:].strip()
    except OSError:
        pass
    return ""


def _match(slug_or_title: str, entries: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Projects whose folder name or title contains the phrase."""
    needle = slug_or_title.strip().lower()
    exact = [e for e in entries if e[0].lower() == needle or e[1].lower() == needle]
    if exact:
        return exact
    return [e for e in entries if needle in e[0].lower() or needle in e[1].lower()]


def list_projects(args: dict) -> ToolResult:
    """Every project in the second brain, newest activity first."""
    projects = _projects_dir()
    if projects is None:
        return ToolResult.error(
            "There is no second brain connected, so there are no projects to list."
        )
    rows: list[tuple[float, str, str]] = []
    try:
        for d in projects.iterdir():
            if not d.is_dir():
                continue
            claude = d / "claude.md"
            try:
                when = claude.stat().st_mtime if claude.is_file() else d.stat().st_mtime
            except OSError:
                when = 0.0
            rows.append((when, d.name, _title_of(claude)))
    except OSError as exc:
        return ToolResult.error(f"Could not read the projects folder: {exc}")

    if not rows:
        return ToolResult(
            content=(
                "The second brain has no projects yet. start_project makes the "
                "first one from something they are actually working on."
            ),
            data={"projects": []},
        )
    rows.sort(reverse=True)
    rows = rows[:_LIST_CAP]
    lines = [f"Projects: {len(rows)}"]
    for _when, slug, title in rows:
        lines.append(f"- {title or slug}" + (f"  ({slug})" if title and title != slug else ""))
    lines.append("Use update_project with the name to add a decision or a note.")
    logger.info("list_projects: %d", len(rows))
    return ToolResult(
        content="\n".join(lines),
        data={"projects": [{"slug": s, "title": t} for _w, s, t in rows]},
    )


def update_project(args: dict) -> ToolResult:
    """Append a decision or a note to a project the operator named."""
    name = str((args or {}).get("project") or "").strip()
    note = str((args or {}).get("note") or "").strip()
    section = str((args or {}).get("section") or "decisions").strip().lower()
    if not name:
        return ToolResult.error("update_project needs the project name.")
    if not note:
        return ToolResult.error("update_project needs the note to add.")
    if len(note) > _MAX_NOTE_CHARS:
        return ToolResult.error(
            f"That note is too long ({len(note)} chars; cap {_MAX_NOTE_CHARS}). "
            "Write the decision, not the conversation."
        )

    projects = _projects_dir()
    if projects is None:
        return ToolResult.error("There is no second brain connected.")

    entries = [
        (d.name, _title_of(d / "claude.md"))
        for d in projects.iterdir()
        if d.is_dir()
    ]
    found = _match(name, entries)
    if not found:
        known = ", ".join(t or s for s, t in entries[:12]) or "none yet"
        return ToolResult.error(
            f"No project called {name!r}. The brain holds: {known}. "
            "Do not invent one; ask which they meant, or offer start_project."
        )
    if len(found) > 1:
        names = ", ".join(t or s for s, t in found)
        return ToolResult.error(
            f"{name!r} matches several projects: {names}. Ask which one before writing."
        )

    slug, title = found[0]
    claude = projects / slug / "claude.md"
    heading = "Notes" if section.startswith("note") else "Key Decisions"
    bullet = f"- {note} _({date.today().isoformat()})_"

    try:
        text = claude.read_text(encoding="utf-8") if claude.is_file() else ""
    except OSError as exc:
        return ToolResult.error(f"Could not read that project: {exc}")

    # [ \t]* rather than \s*: a greedy \s* eats the blank line after the
    # heading, and the insert then adds a second one every time.
    pattern = re.compile(rf"(?m)^##[ \t]+{re.escape(heading)}[ \t]*$")
    m = pattern.search(text)
    if m:
        # Straight after the heading, so the newest entry reads first.
        at = m.end()
        rest = text[at:]
        updated = text[:at] + "\n\n" + bullet + ("\n" + rest.lstrip("\n") if rest.strip() else "\n")
    else:
        updated = text.rstrip("\n") + f"\n\n## {heading}\n\n{bullet}\n"

    try:
        claude.parent.mkdir(parents=True, exist_ok=True)
        claude.write_text(updated, encoding="utf-8", newline="\n")
    except OSError as exc:
        return ToolResult.error(f"Could not write that project: {exc}")

    logger.info("update_project %s <- %s", slug, note[:60])
    return ToolResult(
        content=(
            f"Added to {title or slug} under {heading}: {note[:120]}\n"
            "Confirm briefly, naming the project."
        ),
        data={"project": slug, "title": title, "section": heading, "note": note},
    )
