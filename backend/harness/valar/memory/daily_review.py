"""The first routine's engine: Selene's daily review.

A past day is pending when Thoughts holds diaries for it and Reviews/daily
holds no review of it. The pass reads that day's diaries, runs Selene in a
fresh subagent context to write the review, saves it where the Journal
already looks (Reviews/daily/<date>.md, journal.py's shelf), and appends
each named project's update under its Key Decisions heading.

The clock lives here too, and deliberately in the gateway rather than a
second process: the tray keeps the house alive, so the house's own loop IS
the daily clock. It ticks every half hour, does nothing on machines with
nothing pending, and honors the plain-text record (routines.daily_review_
enabled) so deleting the routine's section stops the clock without a
settings screen. A failed pass stays pending and is retried on a later
tick rather than marked done.
"""

from __future__ import annotations

import asyncio
import logging
import re
from datetime import date, datetime, timedelta
from pathlib import Path

from ..config.settings import hearth_engram
from . import dev_harvest, routines

logger = logging.getLogger("valar.memory.daily_review")

REVIEW_CHECK_S = 1800
# The first tick waits out startup: model warm-up and the first conversation
# outrank a review of yesterday.
FIRST_CHECK_DELAY_S = 300

# Bounds, so a chatty day cannot blow the context: at most this many diaries,
# each cut to this many characters.
_MAX_DIARIES = 8
_MAX_DIARY_CHARS = 4000
_MAX_DAYS_PER_TICK = 2

_DATED_DIR_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-")
_UPDATE_LINE_RE = re.compile(r"^\s*-\s*([A-Za-z0-9][\w-]*)\s*:\s*(.+)$")


def pending_review_days(root: Path, limit: int = _MAX_DAYS_PER_TICK) -> list[str]:
    """Past days with diaries but no review, oldest first, capped."""
    thoughts = Path(root) / "Thoughts"
    if not thoughts.is_dir():
        return []
    today = date.today().isoformat()
    days: set[str] = set()
    for entry in thoughts.iterdir():
        m = _DATED_DIR_RE.match(entry.name)
        # A day of short sessions persists as chatlog.md only (below the
        # diary threshold). Those days still happened: without this, a day
        # of quick voice turns got no review at all (2026-08-18 was the
        # first casualty) and "what did we do yesterday" had nothing to read.
        if entry.is_dir() and m and (
            (entry / "claude.md").is_file() or (entry / "chatlog.md").is_file()
        ):
            days.add(m.group(1))
    reviews = Path(root) / "Reviews" / "daily"
    out = [
        d for d in sorted(days) if d < today and not (reviews / f"{d}.md").is_file()
    ]
    return out[: max(1, limit)]


def day_diaries(root: Path, day: str) -> list[tuple[str, str]]:
    """(slug, bounded text) for each of the day's diaries, name order.
    Falls back to the raw chatlog when a session was too short for a diary."""
    thoughts = Path(root) / "Thoughts"
    out: list[tuple[str, str]] = []
    for entry in sorted(thoughts.iterdir()):
        if not (entry.is_dir() and entry.name.startswith(f"{day}-")):
            continue
        text = ""
        for name in ("claude.md", "chatlog.md"):
            try:
                text = (entry / name).read_text(encoding="utf-8", errors="replace")
                break
            except OSError:
                continue
        if not text:
            continue
        out.append((entry.name, text[:_MAX_DIARY_CHARS]))
        if len(out) >= _MAX_DIARIES:
            break
    return out


def _selene_task(
    day: str, diaries: list[tuple[str, str]], reports: dict[str, str]
) -> str:
    parts = [
        f"Write the daily review for {day}. Below are that day's session "
        "diaries from the house, and then each persona's own report of "
        "their day, in their own words.",
        "Reply with exactly three sections and nothing else:",
        "## Review",
        "One short paragraph: what happened that day and what mattered.",
        "## Project updates",
        "One bullet per project actually worked on, exactly in the form "
        "`- <project-folder-name>: <one line of what was done>`. Only "
        "projects named in the diaries; if none, write `- none`.",
        "## By persona",
        "One short paragraph per persona who filed a report, headed with "
        "their name as `### <Name>`, saying what they did and what came of "
        "it. Use their own report; do not add work they did not claim. A "
        "persona with no report below gets one line: `Unreported.`",
        "",
    ]
    for slug, text in diaries:
        parts.append(f"--- diary {slug} ---")
        parts.append(text)
    for name, report in reports.items():
        parts.append(f"--- {name}'s own report ---")
        parts.append(report)
    return "\n".join(parts)


def _personas():
    """The live persona engine, from the subagent runtime the gateway set."""
    try:
        from ..agents.subagent import _runtime

        return _runtime.get("personas")
    except Exception as exc:  # noqa: BLE001
        logger.warning("daily review: persona engine unavailable (%s)", exc)
        return None


def _persona_paragraph(content: str, name: str) -> str:
    """Selene's `### <Name>` paragraph out of the By persona section."""
    if "## By persona" not in content:
        return ""
    body = content.split("## By persona", 1)[1]
    marker = f"### {name}"
    if marker not in body:
        return ""
    after = body.split(marker, 1)[1]
    for stop in ("\n### ", "\n## "):
        if stop in after:
            after = after.split(stop, 1)[0]
    return after.strip()


def _review_names(content: str) -> list[str]:
    if "## By persona" not in content:
        return []
    body = content.split("## By persona", 1)[1]
    return [
        line.removeprefix("### ").strip()
        for line in body.splitlines()
        if line.startswith("### ")
    ]


def _return_to_authors(personas, day: str, content: str, discrepancies: dict) -> None:
    """Selene's paragraph and any discrepancy go back to the persona that
    wrote the report (spec section 5, back to the author). Appended to its
    own day file, so its next digest carries a line about it."""
    if personas is None:
        return
    from . import persona_memory as pm

    for name in set(list(discrepancies) + _review_names(content)):
        try:
            persona = personas.load(name)
        except Exception:  # noqa: BLE001 - a name Selene invented is not a persona
            continue
        path = Path(persona.memory_dir) / pm.DAY_DIRNAME / f"{day}.md"
        if not path.exists():
            continue
        parts = ["", "## Selene's review"]
        paragraph = _persona_paragraph(content, name)
        if paragraph:
            parts.append(paragraph)
        for line in discrepancies.get(name, []):
            parts.append(f"- Discrepancy: {line}")
        try:
            with path.open("a", encoding="utf-8") as f:
                f.write("\n".join(parts) + "\n")
        except OSError as exc:  # noqa: BLE001
            logger.warning(
                "day report: could not return the review to %s (%s)", name, exc
            )


def _apply_project_updates(root: Path, content: str) -> int:
    """Append `- slug: text` bullets after '## Project updates' to the named
    projects' Key Decisions, for slugs that actually exist. Returns count."""
    try:
        from memory import brain_sync  # type: ignore
    except Exception as exc:  # noqa: BLE001 - memory layer optional
        logger.warning("daily review: brain_sync unavailable (%s)", exc)
        return 0
    section = content.split("## Project updates", 1)
    if len(section) < 2:
        return 0
    applied = 0
    projects = Path(root) / "Projects"
    for line in section[1].splitlines():
        m = _UPDATE_LINE_RE.match(line)
        if not m:
            continue
        slug, update = m.group(1), m.group(2).strip()
        if slug.lower() == "none" or not (projects / slug).is_dir():
            continue
        try:
            result = brain_sync.update_project_context(slug, update)
            if result.get("ok"):
                applied += 1
        except Exception as exc:  # noqa: BLE001 - one bad update never ends the pass
            logger.warning("daily review: update for %s failed (%s)", slug, exc)
    return applied


async def run_review(root: Path, day: str) -> bool:
    """One day's review: the personas report, Python checks them, Selene
    writes it, the Journal's shelf receives it, the projects get their
    lines, and each author gets her paragraph back. False leaves the day
    pending for retry."""
    from ..agents.subagent import run_persona_subagent
    from . import persona_day_report as dr
    from . import persona_receipts, persona_validate

    diaries = day_diaries(root, day)
    if not diaries:
        return False

    # The personas report first: the inbox is an input to the review, and
    # the day's log is complete by the time this runs (spec section 5).
    personas = _personas()
    filed: dict[str, bool] = {}
    if personas is not None:
        try:
            filed = await dr.run_day_reports(personas, day, root)
        except Exception as exc:  # noqa: BLE001 - the review runs without them
            logger.warning("day reports failed for %s: %s", day, exc)
    reports = dr.read_inbox(root, day)

    result = await run_persona_subagent("Selene", _selene_task(day, diaries, reports))
    content = str(result.get("content") or "").strip()
    if not result.get("ok") or "## Review" not in content:
        logger.warning(
            "daily review for %s did not land (%s)", day, result.get("error") or "empty"
        )
        return False

    names = list(filed) or list(reports)
    known = set(names)
    discrepancies: dict[str, list[str]] = {}
    for name, report in reports.items():
        lines = persona_validate.check(
            dr.read_inbox_log(root, day, name), report, known
        )
        if lines:
            discrepancies[name] = lines

    # Receipts and discrepancies are facts, appended by the harness. A
    # receipt a model wrote is not a receipt.
    receipts = persona_receipts.render(root, day, names)
    if receipts:
        content += "\n\n## Receipts\n" + receipts
    if discrepancies:
        content += "\n\n## Discrepancies\n" + "\n".join(
            f"- {name}: {line}"
            for name, lines in discrepancies.items()
            for line in lines
        )

    applied = _apply_project_updates(root, content)
    reviews = Path(root) / "Reviews" / "daily"
    try:
        reviews.mkdir(parents=True, exist_ok=True)
        (reviews / f"{day}.md").write_text(
            f"# {day}\n\n{content}\n\n_Reviewed by Selene, "
            f"{datetime.now().strftime('%Y-%m-%d %H:%M')}._\n",
            encoding="utf-8",
        )
    except OSError as exc:
        logger.warning("daily review: could not write %s (%s)", day, exc)
        return False

    _return_to_authors(personas, day, content, discrepancies)
    logger.info(
        "daily review: %s written, %d project update(s), %d report(s), "
        "%d discrepancy(ies)",
        day,
        applied,
        len(reports),
        sum(len(v) for v in discrepancies.values()),
    )
    return True


async def daily_review_loop() -> None:
    """The routine's clock. Started by the gateway at startup; never raises."""
    await asyncio.sleep(FIRST_CHECK_DELAY_S)
    while True:
        try:
            try:
                root = hearth_engram()
            except Exception:  # noqa: BLE001 - unconfigured memory: idle tick
                root = None
            if root is not None and routines.daily_review_enabled(root):
                # Dev work enters the inbox before the day is judged: harvest
                # yesterday first (a day of only commits is otherwise not
                # pending at all), then each pending day again for replay
                # windows. Both calls are idempotent and blocking-cheap, but
                # git is a subprocess, so they leave the loop's thread.
                yesterday = (date.today() - timedelta(days=1)).isoformat()
                await asyncio.to_thread(dev_harvest.harvest_day, root, yesterday)
                for day in pending_review_days(root):
                    await asyncio.to_thread(dev_harvest.harvest_day, root, day)
                    await run_review(root, day)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the clock outlives any bad tick
            logger.exception("daily review tick failed; continuing")
        await asyncio.sleep(REVIEW_CHECK_S)
