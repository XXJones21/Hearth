"""The day report: a persona's own account of its day, filed to the house.

Spec section 5 of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md. The
persona is asked, never read: the harness renders that persona's own log
into a digest, gives it to the persona in a fresh worker context, and
writes what comes back. The report goes to the persona's own day/ folder
AND to Engram/Inbox/<day>/, which is the one place its work becomes
readable by anyone else, and only after Selene's review has run.

A persona with nothing in its log for the day files nothing. The review
names it unreported rather than inventing a paragraph for it.
"""

from __future__ import annotations

import json
import logging
import shutil
from datetime import date, datetime, timedelta
from pathlib import Path

from . import persona_memory as pm

logger = logging.getLogger("valar.memory.day_report")

INBOX_REL = "Inbox"
MAX_ENTRIES = 40
MAX_REPORT_CHARS = 4000
KEEP_DAYS = 14

_TASK = (
    "Below is your own record of {day}. Read what it can and cannot vouch "
    "for.\n\n"
    "ASKED and TOUCHED are facts: what the operator put to you, and the "
    "tools you actually ran and on what. YOU SAID is your own words, which "
    "prove nothing. Where a turn says you answered from the house's shared "
    "record, the answer itself is withheld on purpose: it described "
    "everyone's day, not yours, and it is not yours to report.\n\n"
    "Report each thing at the size it actually happened. Reading a file's "
    "first heading is reading a heading; it is not refining, reviewing or "
    "documenting that file. If the only trace of something is that you were "
    "asked about it, then you were asked about it, and that is all.\n\n"
    "Write your report of {day} for the house. Two short paragraphs at "
    "most, as yourself, in the first person. Say what YOU did and what came "
    "of it, in your own voice. Do not list the tools you used; nobody wants "
    "an inventory of verbs. Do not claim work another persona did. Do not "
    "invent anything that is not below. If your day was thin, say so "
    "plainly; a quiet day is a finding, not a gap to fill.\n\n"
    "--- your record of {day} ---\n{digest}"
)


# Tools that read the HOUSE's shared record rather than this persona's own.
# A turn that ran one of these answered about everyone, so its answer is not
# evidence of anything this persona did, and labelling it was not enough:
# Soth reported a whole day of Superset work it never touched, purely from
# three such answers (2026-09-03).
_SHARED_READS = frozenset(
    {
        "search_journal",
        "consult_memory",
        "recall",
        "project_status",
        "list_projects",
        "search_files",
    }
)


def _read_the_house(entry: dict) -> bool:
    names = {str(t).split(" ")[0] for t in (entry.get("touched") or [])}
    return bool(names & _SHARED_READS)


def _is_machinery(entry: dict) -> bool:
    """A turn the report machinery itself made, which is not part of the day.

    The day report's own dispatch and Selene's review dispatch both land in
    the persona's log like any other turn, so without this a report describes
    the writing of itself.
    """
    origin = str(entry.get("origin") or "")
    if origin.startswith("routine/day-report"):
        return True
    question = str(entry.get("question") or "")
    return question.startswith("Write the daily review for ") or question.startswith(
        "Below is your own record of "
    )


def day_digest(root: Path, day: str) -> str:
    entries = [e for e in pm.read_log(root, day) if not _is_machinery(e)]
    if not entries:
        return ""
    sessions = {r["id"]: r for r in pm.read_sessions(root)}
    lines: list[str] = []
    for e in entries[:MAX_ENTRIES]:
        when = str(e.get("ts") or "")[11:16]
        origin = str(e.get("origin") or "")
        client = str(e.get("client") or "")
        row = sessions.get(str(e.get("session") or ""), {})
        lines.append(f"{when} [{origin or client}] {row.get('title') or ''}".rstrip())
        if e.get("question"):
            lines.append(f"  ASKED: {e['question']}")
        touched = e.get("touched") or []
        if touched:
            lines.append("  TOUCHED: " + "; ".join(str(t) for t in touched))
        if e.get("dispatches"):
            lines.append("  ASKED OF: " + ", ".join(e["dispatches"]))
        # An answer is this persona's own words, so it is never evidence.
        # When the turn read the house's shared record, the answer describes
        # everyone's day and is REMOVED rather than labelled: labelling was
        # tried on 2026-09-03 and the personas used it anyway.
        if e.get("answer"):
            if _read_the_house(e):
                lines.append("  (you answered from the house's shared record)")
            else:
                lines.append(f"  YOU SAID: {e['answer']}")
    if len(entries) > MAX_ENTRIES:
        lines.append(f"({len(entries) - MAX_ENTRIES} more turns not listed.)")
    return "\n".join(lines)


def inbox_dir(engram_root: Path, day: str) -> Path:
    return Path(engram_root) / INBOX_REL / day


def _write_inbox(
    engram_root: Path, day: str, name: str, report: str, entries: list
) -> None:
    folder = inbox_dir(engram_root, day)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.md").write_text(
        f"# {name}, {day}\n\n{report.strip()}\n", encoding="utf-8"
    )
    (folder / f"{name}.log.json").write_text(
        json.dumps(list(entries), ensure_ascii=False, indent=2), encoding="utf-8"
    )


async def file_report(personas, name: str, day: str, engram_root: Path | None) -> bool:
    """One persona's report. False means nothing was filed, for any reason."""
    from ..agents.subagent import run_persona_subagent

    try:
        persona = personas.load(name)
    except Exception as exc:  # noqa: BLE001
        logger.warning("day report: %s unavailable (%s)", name, exc)
        return False
    root = Path(persona.memory_dir)
    digest = day_digest(root, day)
    if not digest:
        logger.info("day report: %s has no record of %s, nothing filed", name, day)
        return False

    result = await run_persona_subagent(
        name, _TASK.format(day=day, digest=digest), origin="routine/day-report"
    )
    report = str(result.get("content") or "").strip()[:MAX_REPORT_CHARS]
    if not result.get("ok") or not report:
        logger.warning(
            "day report: %s did not answer (%s)", name, result.get("error") or "empty"
        )
        return False

    path = root / pm.DAY_DIRNAME / f"{day}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"# {day}\n\n{report}\n\n_Filed {datetime.now().strftime('%Y-%m-%d %H:%M')}._\n",
        encoding="utf-8",
    )
    if engram_root is not None:
        try:
            _write_inbox(engram_root, day, name, report, pm.read_log(root, day))
        except OSError as exc:
            logger.warning("day report: inbox copy for %s failed (%s)", name, exc)
    logger.info("day report: %s filed %s (%d chars)", name, day, len(report))
    return True


async def run_day_reports(
    personas, day: str, engram_root: Path | None
) -> dict[str, bool]:
    """Every resident persona, one at a time. One failure never stops the rest."""
    filed: dict[str, bool] = {}
    for name in personas.list_personas(platform="desktop"):
        try:
            filed[name] = await file_report(personas, name, day, engram_root)
        except Exception as exc:  # noqa: BLE001
            logger.warning("day report for %s raised: %s", name, exc)
            filed[name] = False
    return filed


def read_inbox(engram_root: Path, day: str) -> dict[str, str]:
    folder = inbox_dir(engram_root, day)
    if not folder.is_dir():
        return {}
    out: dict[str, str] = {}
    for f in sorted(folder.glob("*.md")):
        try:
            out[f.stem] = f.read_text(encoding="utf-8")
        except OSError:
            continue
    return out


def read_inbox_log(engram_root: Path, day: str, name: str) -> list[dict]:
    path = inbox_dir(engram_root, day) / f"{name}.log.json"
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return data if isinstance(data, list) else []


def prune_inbox(engram_root: Path, keep_days: int = KEEP_DAYS) -> int:
    """Inbox folders past the window go; the reviews and the databases keep
    everything they held (spec section 5, the week clock)."""
    base = Path(engram_root) / INBOX_REL
    if not base.is_dir():
        return 0
    cutoff = (date.today() - timedelta(days=keep_days)).isoformat()
    removed = 0
    for folder in sorted(base.iterdir()):
        if folder.is_dir() and len(folder.name) == 10 and folder.name < cutoff:
            try:
                shutil.rmtree(folder)
                removed += 1
            except OSError as exc:  # noqa: BLE001
                logger.warning("inbox prune failed for %s: %s", folder.name, exc)
    return removed
