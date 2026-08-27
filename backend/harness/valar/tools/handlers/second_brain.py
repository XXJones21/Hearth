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
import os
import re
from datetime import date
from pathlib import Path

from ...config.settings import hearth_engram, hearth_home, hearth_root
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.second_brain")

# The four quarters every brain has; also the shape test for an import.
_BRAIN_FOLDERS = ("Projects", "Areas", "Thoughts", "Resources")

# Written to hearth_home() when setup finishes without a first project (a
# decline, or an import that brought its own history). first_run.brain_beat_open
# reads it, so "consider this complete" actually completes something now.
COMPLETE_MARKER = "second-brain-complete"


def _mark_complete(note: str) -> None:
    try:
        marker = hearth_home() / COMPLETE_MARKER
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(f"{note}\n{date.today().isoformat()}\n", encoding="utf-8")
    except Exception as exc:  # noqa: BLE001 - the beat still closes via Projects
        logger.warning("second brain: could not write the complete marker (%s)", exc)


def _hearth_env_candidates() -> list[Path]:
    """Every place this product's launchers look for hearth.env, best first.

    There are two shipping layouts and they sit one directory apart, which is
    the whole reason this needs saying out loud:

    - An INSTALLED desktop house has an install root holding config/, home/,
      models/ and runtime/ side by side. hearth_probe::defaults fixes that
      shape (``REL_CONFIG = "config/hearth.env"``, ``REL_HOME = "home"``),
      config_gen.rs renders HEARTH_HOME=<root>/home, and desktop-client
      house.rs reads <root>/config/hearth.env. So the file is at
      ``HEARTH_HOME/../config``.
    - A SYSTEMD or WSL testbed house sets HEARTH_HOME=~/.hearth and keeps the
      file INSIDE it, which is what all three units name outright as
      ``EnvironmentFile=-%h/.hearth/config/hearth.env`` and what
      render_config.py defaults to.

    Picking either one alone strands the other: writing only to the installed
    path leaves a testbed's edits unread, and writing only to the testbed path
    leaves the shipping product's edits unread. Both are returned, and the
    file that already exists decides, because that is the one this house was
    actually launched from.
    """
    out: list[Path] = []
    # HEARTH_BACKEND_DIR is the strongest signal there is: the installer always
    # writes it, config_gen.rs renders it as <root>/runtime/backend, and the
    # install root two levels up is where REL_CONFIG puts hearth.env. It is
    # preferred over HEARTH_HOME because HEARTH_HOME can be pointed anywhere by
    # a custom launch (one house had it on the source checkout), and when it is,
    # deriving the config path from it lands the file somewhere nothing loads.
    backend_dir = (os.environ.get("HEARTH_BACKEND_DIR") or "").strip()
    if backend_dir:
        out.append(Path(backend_dir).expanduser().parent.parent / "config" / "hearth.env")
    try:
        # HEARTH_ROOT, when exported, IS the install root.
        out.append(hearth_root() / "config" / "hearth.env")
    except Exception:  # noqa: BLE001 - no product marker on a bare dev run
        pass
    home = hearth_home()
    for p in (home.parent / "config" / "hearth.env", home / "config" / "hearth.env"):
        out.append(p)
    seen: set[Path] = set()
    return [p for p in out if not (p in seen or seen.add(p))]


def _hearth_env_path() -> Path:
    """Which hearth.env to write. An existing file always wins."""
    candidates = _hearth_env_candidates()
    for p in candidates:
        if p.is_file():
            return p
    # Nothing on disk yet, so infer the layout. An explicitly set HEARTH_HOME
    # came from an installer that put config/ beside home/; an unset one is
    # the ~/.hearth default, where the units expect config/ inside it.
    home = hearth_home()
    if (os.environ.get("HEARTH_HOME") or "").strip():
        return home.parent / "config" / "hearth.env"
    return home / "config" / "hearth.env"


def _rewrite_hearth_env(root: str) -> bool:
    """Point HEARTH_ENGRAM at `root` in hearth.env, so restarts keep the
    bridge. Creates the file, and its directory, when they do not exist.

    It used to read the file first and return False on any OSError, so a
    house whose launcher had never written a hearth.env repointed its memory
    for the running process only and forgot on the next start. The caller
    still announced the bridge built. That is precisely the 2026-08-08
    hallucination this module was written to end, moved one layer down out of
    the persona and into the code -- which is why a missing file is now a
    thing to create rather than a reason to stop.
    """
    env_path = _hearth_env_path()
    try:
        lines = env_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    out, seen = [], False
    for ln in lines:
        if ln.startswith("HEARTH_ENGRAM="):
            out.append(f"HEARTH_ENGRAM={root}")
            seen = True
        else:
            out.append(ln)
    if not seen:
        out.append(f"HEARTH_ENGRAM={root}")
    try:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        env_path.write_text("\n".join(out) + "\n", encoding="utf-8")
    except OSError as exc:
        logger.warning("second brain: hearth.env not written at %s (%s)", env_path, exc)
        return False
    return True


def link_brain(path: str, *, allow_new: bool = False) -> dict:
    """Point this house at a memory tree, or refuse and say why.

    The one implementation of the bridge. `import_brain` is the conversational
    caller and Settings is the deliberate one; they must not drift, because the
    rule they share is the product's only defence against a house adopting a
    stranger's memory and presenting it as the new owner's.

    A tree qualifies when it already carries one of the four quarters. With
    `allow_new`, a COMPLETELY EMPTY directory also qualifies and is provisioned
    the way a fresh install would be: someone choosing a folder in Settings may
    reasonably mean "start a brain here", while a conversation naming a path
    never does. A directory with other things in it is refused either way,
    because writing four folders into someone's Documents is not a small
    mistake.

    Returns a dict rather than a ToolResult so the HTTP surface does not have
    to parse prose written for a persona to speak.
    """
    raw = str(path or "").strip().strip('"').strip("'")
    if not raw:
        return {"ok": False, "error": "No path given. Nothing was changed."}
    target = Path(raw.replace("\\", "/")).expanduser()
    if not target.is_absolute():
        return {
            "ok": False,
            "error": (
                "That path is not absolute. Give the full path, from the drive "
                "letter or root down, so the house never guesses at whose "
                "memory it is opening."
            ),
        }
    if not target.is_dir():
        return {"ok": False, "error": f"There is no folder at {target}. Nothing was changed."}

    present = [f for f in _BRAIN_FOLDERS if (target / f).is_dir()]
    created = False
    if not present:
        empty = False
        try:
            empty = not any(target.iterdir())
        except OSError as exc:
            return {"ok": False, "error": f"{target} could not be read ({exc})."}
        if not (allow_new and empty):
            return {
                "ok": False,
                "error": (
                    f"{target} does not look like a brain: none of Projects, "
                    "Areas, Thoughts or Resources live inside it, and it is not "
                    "empty. Nothing was changed."
                ),
            }
        created = True

    root = str(target).replace("\\", "/")
    os.environ["HEARTH_ENGRAM"] = root
    env_path = _hearth_env_path()
    persisted = _rewrite_hearth_env(root)
    # The missing quarters, same as a fresh install provisions them.
    for name in _BRAIN_FOLDERS:
        try:
            (target / name).mkdir(exist_ok=True)
        except OSError:
            pass
    _mark_complete(f"{'started' if created else 'imported'} {root}")
    try:
        from ...memory.routines import ensure_first_routine

        ensure_first_routine(target)
    except Exception as exc:  # noqa: BLE001 - the bridge is the commit; the routine is a rider
        logger.warning("link_brain: routine rider skipped (%s)", exc)

    entries = sum(
        1 for f in _BRAIN_FOLDERS if (target / f).is_dir() for _ in (target / f).iterdir()
    )
    logger.info(
        "second brain: linked %s (%s, %d entries, env %s -> %s)",
        root,
        "new tree" if created else ", ".join(present),
        entries,
        "persisted" if persisted else "NOT persisted",
        env_path,
    )
    return {
        "ok": True,
        "path": root,
        "entries": entries,
        "created": created,
        "persisted": persisted,
        # Named, not just flagged. "persisted: true" pointing at a file no
        # launcher reads is indistinguishable from working, and was.
        "env_path": str(env_path),
    }


def unlink_brain() -> dict:
    """Disconnect the memory tree without deleting a single file of it.

    HEARTH_ENGRAM goes empty in the running process and in hearth.env, which
    is the same state a machine is in before anyone answers the question. The
    Journal reports no tree, memory recall degrades to nothing, and the house
    keeps working. The tree itself is untouched: this is unplugging, not
    erasing, and a Settings row that could destroy a decade of notes would be
    a different kind of control entirely.
    """
    previous = (os.environ.get("HEARTH_ENGRAM") or "").strip()
    os.environ["HEARTH_ENGRAM"] = ""
    persisted = _rewrite_hearth_env("")
    logger.info(
        "second brain: unlinked %s (env %s)",
        previous or "(none)",
        "persisted" if persisted else "NOT persisted",
    )
    return {"ok": True, "path": "", "previous": previous, "persisted": persisted}


def import_brain(path: str = "", **_: object) -> ToolResult:
    """Bridge the house to a second brain the person already has.

    Born from a hallucination (2026-08-08): told about an existing Engram,
    the persona announced "consider the bridge built" having built nothing.
    This is the real bridge: HEARTH_ENGRAM repointed for the running process
    and in hearth.env for every later launch, so the memory layer, the
    Journal, and the MCP mount (which all read that one variable) follow.

    The anti-adoption law holds: the path must be explicit and absolute, and
    it must already look like a brain. A house must never guess at whose
    memory it is opening.
    """
    if not str(path or "").strip():
        return ToolResult(
            ok=False,
            content="I need the exact folder path of the existing brain before anything can be connected.",
        )
    # allow_new stays False here: a conversation naming a path means "the brain
    # I already have", never "make one where I pointed".
    result = link_brain(str(path), allow_new=False)
    if not result.get("ok"):
        return ToolResult(ok=False, content=str(result.get("error") or "Nothing was changed."))

    root = str(result["path"])
    entries = int(result.get("entries") or 0)
    persisted = bool(result.get("persisted"))
    # A bridge that does not survive a restart is a bridge worth mentioning.
    # Reporting only the happy half is the hallucination this tool replaced.
    caveat = (
        ""
        if persisted
        else (
            " Then tell them the one caveat, plainly and without alarm: the "
            "house could not write its own settings file, so this connection "
            "holds for now but a restart will forget it, and they should set "
            "the path again under Settings."
        )
    )
    return ToolResult(
        ok=True,
        content=(
            f"The bridge is real now: this house reads and writes the memory at "
            f"{root}, which already holds {entries} entr"
            + ("y" if entries == 1 else "ies")
            + ". Tell them plainly it is connected, and that everything the house "
            "learns lands there from now on."
            + caveat
        ),
        data={"brain_imported": root, "entries": entries, "persisted": persisted},
    )


def complete_brain_setup(**_: object) -> ToolResult:
    """The beat's legitimate exit: they declined a first project, or said they
    are done. Before this existed, "consider this complete" completed nothing
    and the person was locked in front of a disabled button."""
    _mark_complete("finished without a first project")
    logger.info("second brain: setup marked complete without a project")
    return ToolResult(
        ok=True,
        content=(
            "Setup is complete and the house is theirs. Say a short goodbye to "
            "the setup, and let them know the memory stands ready whenever "
            "something worth keeping comes along."
        ),
        data={"brain_setup_complete": True},
    )

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

    # The first routine rides the same commit: the one moment the person
    # already understands what the brain is, so the one sentence of
    # explanation lands. The record is the switch (routines.py).
    routine_note = ""
    try:
        from ...memory.routines import ensure_first_routine

        if ensure_first_routine(root):
            routine_note = (
                " The house's first routine is recorded as well. Tell them, in "
                "one sentence of your own: each day Selene, the house's "
                "librarian, will review what was talked about and keep this "
                "project up to date, and that standing habit is called a "
                "routine, kept in Areas/routines.md for them to change or "
                "remove."
            )
    except Exception as exc:  # noqa: BLE001 - the project is the commit; the routine is a rider
        logger.warning("start_project: first routine not recorded (%s)", exc)

    return ToolResult(
        ok=True,
        content=f"{title} now has a place in your memory.{routine_note}",
        data={"project": slug, "title": title, "created": True},
    )
