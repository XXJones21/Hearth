"""start_project -- the commit at the end of the second-brain beat.

The third beat of first run, and the mirror of create_persona: a conversation
that ends in one real thing on disk. The person names something they are
actually working on, and it becomes the first directory under
$HEARTH_ENGRAM/Projects. An empty brain is intimidating; a brain with one true
thing in it is a start.

Seed empty, never clone. That is a standing product constraint rather than a
preference (wiki/first-run.md, wiki/backend/portability-ledger.md section 8),
and it is why this writes one directory from what the person said rather than
importing a template, an example set, or anyone else's tree.

The four folders already exist -- the installer creates Projects, Areas,
Resources and Thoughts empty at render time -- so this does not build the
structure. It puts the first thing into it.
"""

from __future__ import annotations

import logging
import re
from datetime import date
from pathlib import Path

from ...config.settings import hearth_engram
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.second_brain")

# A directory name, not a title. The title keeps its capitals and spaces inside
# the file; the folder has to survive every filesystem the product ships on.
_SLUG_STRIP = re.compile(r"[^a-z0-9]+")

# Long enough to say what it is, short enough to be a folder.
_MAX_TITLE = 60


def _slug(title: str) -> str:
    s = _SLUG_STRIP.sub("-", (title or "").strip().lower()).strip("-")
    return s[:48] or "project"


def start_project(name: str = "", note: str = "", **_: object) -> ToolResult:
    """Create the first project under the person's own memory root.

    Args:
        name: what they are working on, in their words.
        note: one or two lines of what it is, for the file's opening.
    """
    title = (name or "").strip()
    if not title:
        return ToolResult(
            ok=False,
            content="I need to know what it is before I can make a place for it.",
        )
    if len(title) > _MAX_TITLE:
        title = title[:_MAX_TITLE].rstrip()

    try:
        root = hearth_engram()
    except Exception as exc:  # noqa: BLE001 - unconfigured memory is not fatal to the turn
        logger.warning("start_project: no engram root (%s)", exc)
        return ToolResult(
            ok=False,
            content="I could not find where your memory lives, so I have not written anything.",
        )

    projects = root / "Projects"
    slug = _slug(title)
    target = projects / slug

    # Never overwrite. A second call with the same name is the person changing
    # their mind mid-sentence, not a request to clobber what is already there.
    if target.exists():
        return ToolResult(
            ok=True,
            content=f"{title} is already here.",
            data={"project": slug, "title": title, "created": False},
        )

    # `Key Decisions` is not decoration: brain_sync.update_project_context()
    # appends under exactly that heading, so a project created here is one the
    # rest of the memory layer can already write to.
    opening = (note or "").strip()
    body = f"# {title}\n\n"
    if opening:
        body += f"{opening}\n\n"
    body += (
        "## Key Decisions\n\n"
        "## Notes\n\n"
        f"_Started {date.today().isoformat()}._\n"
    )

    try:
        target.mkdir(parents=True, exist_ok=False)
        (target / "claude.md").write_text(body, encoding="utf-8")
    except OSError as exc:
        logger.warning("start_project: could not write %s (%s)", target, exc)
        return ToolResult(
            ok=False,
            content="I could not write that to disk, so nothing was saved.",
        )

    logger.info("second brain: first project created at Projects/%s", slug)
    return ToolResult(
        ok=True,
        content=f"{title} now has a place in your memory.",
        data={"project": slug, "title": title, "created": True},
    )
