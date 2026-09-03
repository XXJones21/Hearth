"""Soth's daily push routine: the first persona routine on the house clock.

The shape is journal_sync's, deliberately: an asyncio loop the gateway starts,
a self-describing section in ``Engram/Areas/routines.md`` whose presence IS
the switch, and ticks that never raise. What is new is the front half, taken
from the Hermes v0.21 audit (tasks/projects/gtm-strategist-persona.md, Phase 2
design) with their two continuity bugs corrected:

MONITOR GATE. An unchanged day must cost zero inference. Before any model
work, the tick runs a deterministic sweep (git log since the last watermark
across the Valinor and Hearth checkouts, plus content hashes of the task
files) and compares a SHA-256 of the sweep text against the stored one.
Unchanged means one appended log line and nothing else.

CONTINUITY. A real run reads the tail of the previous REAL report, never a
skip record: skip lines go to a separate runlog, and the state file points at
the last real report by path, so a quiet week cannot poison the next run's
"previous output" (the Hermes newest-by-mtime bug). The watermark and hash
are persisted only AFTER a successful run, so a change that hits a failed run
re-alerts next tick instead of being silently consumed (their
hash-before-run bug), bounded by a failure streak.

The routine definition (schedule, task template) lives in
``Persona/Soth/routines.yaml`` so the live house reads it through the persona
overlay without a harness deploy. The sweep excludes the tracker's own output
directory: a routine whose report changes its own change detector never goes
quiet.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import subprocess
from datetime import datetime
from pathlib import Path

logger = logging.getLogger("valar.soth_routine")

CHECK_S = 1800.0
FIRST_CHECK_DELAY_S = 420.0
_MAX_GIT_LINES = 100
_MAX_FILE_LINES = 100
_MAX_PREV_REPORT_CHARS = 8000
_MAX_FAILURE_STREAK = 3

_ROUTINE_BLOCK_TMPL = """
## {title}

- **Who:** Soth
- **When:** {schedule}, on the house routine clock
- **What:** sweeps what changed in the house (commits and task files), and
  when something did, writes the daily push report into
  tasks/GTM/content/runs/. An unchanged day costs no model work at all.
- **Stop it:** delete this section.
"""


# --------------------------------------------------------------------- config
def _repo_root() -> Path:
    """The household root. Under the Valinor overlay HEARTH_HOME is the
    Valinor checkout, which carries the tracker tree and the Engram junction;
    a vanilla install never reaches these paths because no shipped persona
    carries a routines.yaml."""
    from ..config.settings import hearth_home

    return Path(hearth_home())


def load_routines(persona_dir: Path) -> list[dict]:
    """Every persona's routines.yaml, flattened. Today that is Soth's."""
    import yaml

    out: list[dict] = []
    for path in sorted(persona_dir.glob("*/routines.yaml")):
        try:
            doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except Exception as exc:  # noqa: BLE001 - one bad file never stops the clock
            logger.warning("soth routine: %s unreadable (%s)", path, exc)
            continue
        for r in doc.get("routines") or []:
            if isinstance(r, dict) and r.get("name") and r.get("persona"):
                out.append(r)
    return out


def _parse_daily(schedule: str) -> tuple[int, int]:
    """'daily HH:MM' -> (hour, minute). Anything else means 09:00."""
    try:
        _, clock = str(schedule or "").strip().split()
        h, m = clock.split(":")
        return max(0, min(23, int(h))), max(0, min(59, int(m)))
    except (ValueError, AttributeError):
        return 9, 0


# ---------------------------------------------------------------------- state
def _state_path() -> Path:
    return _repo_root() / "Engram" / "state" / "soth-routine.json"


def _load_state() -> dict:
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_state(state: dict) -> None:
    path = _state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(state, indent=2), encoding="utf-8", newline="\n")
    except OSError as exc:
        logger.warning("soth routine: state not saved (%s)", exc)


# ---------------------------------------------------------------------- sweep
def _git(repo: Path, *args: str) -> str:
    try:
        res = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True, text=True, timeout=30, check=False,
        )
        return res.stdout if res.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _sweep_repos() -> list[Path]:
    roots = [_repo_root()]
    hearth = Path("D:/Tools/Hearth")
    if (hearth / ".git").exists():
        roots.append(hearth)
    return roots


def sweep(state: dict) -> tuple[str, str, list[str]]:
    """The deterministic change sweep. Returns (canonical_text, digest,
    file_lines).

    canonical_text is hashed for the gate; digest is the capped human-readable
    version handed to the model on a change. No timestamps anywhere in the
    canonical text: exact bytes are the comparison, the Hermes lesson. The
    canonical text is ABSOLUTE state (HEAD hashes + file hashes), never the
    watermark-relative log: a delta re-described from a moved watermark reads
    as change when nothing changed (found on the first two-run proof,
    2026-08-31). The log lines exist only for the model's digest.
    """
    marks = state.get("watermarks") or {}
    head_lines: list[str] = []
    git_lines: list[str] = []
    for repo in _sweep_repos():
        head = _git(repo, "rev-parse", "HEAD").strip()
        head_lines.append(f"{repo.name} HEAD {head}")
        wm = str(marks.get(repo.name) or "")
        if wm and head and wm != head:
            log = _git(repo, "log", "--oneline", f"{wm}..HEAD")
        elif not wm:
            log = _git(repo, "log", "--oneline", "-20")
        else:
            log = ""
        for ln in log.splitlines():
            git_lines.append(f"{repo.name} {ln.strip()}")

    file_lines: list[str] = []
    for repo in _sweep_repos():
        tasks = repo / "tasks"
        if not tasks.is_dir():
            continue
        for md in sorted(tasks.rglob("*.md")):
            rel = md.relative_to(repo).as_posix()
            # The tracker's own outputs must not trip the tracker.
            if rel.startswith("tasks/GTM/content/"):
                continue
            try:
                h = hashlib.sha256(md.read_bytes()).hexdigest()[:12]
            except OSError:
                continue
            file_lines.append(f"{repo.name}/{rel} {h}")

    canonical = "\n".join(head_lines + sorted(file_lines))

    # The digest: what changed, not the whole world. File hashes are compared
    # against the previous sweep's to name only the edited files.
    prev_files = set(state.get("file_hashes") or [])
    changed_files = [ln for ln in file_lines if ln not in prev_files]
    digest_parts: list[str] = []
    if git_lines:
        digest_parts.append("New commits:\n" + "\n".join(git_lines[:_MAX_GIT_LINES]))
    if changed_files:
        digest_parts.append(
            "Task files changed:\n"
            + "\n".join(ln.rsplit(" ", 1)[0] for ln in changed_files[:_MAX_FILE_LINES])
        )
    if not digest_parts:
        digest_parts.append("First run, or change detected outside the digest scope.")
    return canonical, "\n\n".join(digest_parts), file_lines


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


# ------------------------------------------------------------------- routines
def _routines_file() -> Path:
    return _repo_root() / "Engram" / "Areas" / "routines.md"


def ensure_routine(title: str, schedule: str) -> None:
    path = _routines_file()
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        if title.lower() in text.lower():
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8", newline="\n") as fh:
            if text and not text.endswith("\n"):
                fh.write("\n")
            fh.write(_ROUTINE_BLOCK_TMPL.format(title=title, schedule=schedule))
    except OSError as exc:
        logger.warning("soth routine: routine record not written (%s)", exc)


def routine_enabled(title: str) -> bool:
    try:
        return title.lower() in _routines_file().read_text(encoding="utf-8").lower()
    except OSError:
        return False


# --------------------------------------------------------------------- output
def _runs_dir() -> Path:
    return _repo_root() / "tasks" / "GTM" / "content" / "runs"


def _append_runlog(line: str) -> None:
    path = _runs_dir() / "runlog.md"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        header = "" if path.exists() else "# Soth routine log\n\nOne line per tick that did work or skipped. Reports live beside this file.\n\n"
        with path.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(f"{header}- {datetime.now().strftime('%Y-%m-%d %H:%M')} {line}\n")
    except OSError as exc:
        logger.warning("soth routine: runlog append failed (%s)", exc)


def _append_engram_runlog(line: str) -> None:
    path = _repo_root() / "Engram" / "Projects" / "soth" / "claude.md"
    try:
        with path.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(f"- {datetime.now().strftime('%Y-%m-%d %H:%M')} {line}\n")
    except OSError as exc:
        logger.warning("soth routine: engram runlog append failed (%s)", exc)


def _prev_report_tail(state: dict) -> str:
    rel = str(state.get("last_report") or "")
    if not rel:
        return ""
    try:
        text = (_repo_root() / rel).read_text(encoding="utf-8")
    except OSError:
        return ""
    return text[-_MAX_PREV_REPORT_CHARS:]


# ----------------------------------------------------------------------- tick
def _due(routine: dict, state: dict, now: datetime) -> bool:
    hour, minute = _parse_daily(str(routine.get("schedule") or ""))
    if (now.hour, now.minute) < (hour, minute):
        return False
    return str(state.get("last_tick_date") or "") != now.strftime("%Y-%m-%d")


async def run_tick(routine: dict, force: bool = False) -> str:
    """One routine pass. Returns an outcome word for the caller's log."""
    title = str(routine.get("title") or routine.get("name") or "Soth daily push")
    schedule = str(routine.get("schedule") or "daily 09:00")
    ensure_routine(title, schedule)
    if not routine_enabled(title):
        return "disabled"

    now = datetime.now()
    state = _load_state()
    if not force and not _due(routine, state, now):
        return "not_due"

    canonical, digest, file_lines = await asyncio.to_thread(sweep, state)
    new_hash = _hash(canonical)
    # The date stamp is written even on a skip: due-ness is per day, and a
    # quiet day is a completed day. The HASH is only written on success below.
    state["last_tick_date"] = now.strftime("%Y-%m-%d")

    if state.get("last_hash") == new_hash:
        _save_state(state)
        _append_runlog("no change; run suppressed, no model work")
        return "no_change"

    from .subagent import run_persona_subagent, subagents_ready

    if not subagents_ready():
        _save_state(state)
        return "no_runtime"

    task = str(routine.get("task") or "Run your daily push sweep.")
    prev = _prev_report_tail(state)
    parts = [task, "## What changed since your last run\n\n" + digest]
    if prev:
        parts.append("## Tail of your previous report\n\n" + prev)
    res = await run_persona_subagent(
        str(routine["persona"]), "\n\n".join(parts), origin="routine"
    )

    if not res.get("ok") or not (res.get("content") or "").strip():
        streak = int(state.get("failure_streak") or 0) + 1
        state["failure_streak"] = streak
        # Watermark and hash deliberately NOT advanced: the change re-alerts.
        _save_state(state)
        _append_runlog(
            f"run FAILED (streak {streak}): {res.get('error') or 'empty answer'}"
        )
        if streak == _MAX_FAILURE_STREAK:
            _append_engram_runlog(
                f"routine failing, streak {streak}; see tasks/GTM/content/runs/runlog.md"
            )
        return "failed"

    report_name = f"{now.strftime('%Y-%m-%d_%H%M')}_soth.md"
    report_path = _runs_dir() / report_name
    try:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            f"# Soth run report, {now.strftime('%Y-%m-%d %H:%M')}\n\n"
            + res["content"].strip() + "\n",
            encoding="utf-8", newline="\n",
        )
    except OSError as exc:
        logger.warning("soth routine: report not written (%s)", exc)
        return "failed"

    # Success is the only moment the gate advances.
    state["last_hash"] = new_hash
    state["file_hashes"] = file_lines
    state["watermarks"] = {
        repo.name: _git(repo, "rev-parse", "HEAD").strip() for repo in _sweep_repos()
    }
    state["failure_streak"] = 0
    state["last_report"] = report_path.relative_to(_repo_root()).as_posix()
    state["last_success_at"] = now.strftime("%Y-%m-%d %H:%M")
    _save_state(state)
    rel = state["last_report"]
    _append_runlog(f"report written: {rel} (tools={res.get('tools_used') or []})")
    _append_engram_runlog(f"run report: {rel}")
    logger.info("soth routine: %s", rel)
    return "report"


async def soth_routine_loop(personas, brain, config) -> None:
    """The routine clock. Started by the gateway; never raises."""
    await asyncio.sleep(FIRST_CHECK_DELAY_S)
    while True:
        try:
            for routine in load_routines(Path(config.persona_dir)):
                outcome = await run_tick(routine)
                if outcome not in ("not_due", "no_change", "disabled"):
                    logger.info("soth routine tick: %s -> %s", routine.get("name"), outcome)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the clock outlives any bad tick
            logger.exception("soth routine tick failed; continuing")
        await asyncio.sleep(CHECK_S)
