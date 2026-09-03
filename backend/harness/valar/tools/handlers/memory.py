"""Memory tool -- voice-callable recall + remember, ported from the Telegram bot.

The Telegram bot (``scripts/sulivan_telegram_bot.py``) already proved this pattern:
``/remember`` dual-writes a fact to Engram's shared ``operator-facts`` file, and
``/recall`` substring-searches it. Here those verbs become voice tools backed by
the *same* Engram helpers (``Server.tools.brain_sync.add_operator_fact`` /
``search_operator_facts`` / ``load_operator_facts``), so the Echo voice path and
the Telegram bot share one memory store.

Standalone + defensive: the brain_sync import is lazy and guarded (the same
degrade-to-empty contract as ``valar.memory.EngramMemory``); if Engram is
unavailable the tools return a graceful message instead of throwing, so a turn is
never broken by a memory miss. No Valar state, no event loop assumptions.
"""

from __future__ import annotations

import difflib
import logging
import re
import sys
from datetime import date, timedelta
from pathlib import Path

from ...config.settings import hearth_engram
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.memory")


# Knowledge tier (2026-06-06): operator-facts alone is NOT the operator's
# memory -- the rich background (career history, project context) lives in
# Engram's context files. recall searches these as a second tier so "what
# about my time at Meta" finds the Career notes, not just /remember'd facts.
_ENGRAM_ROOT = hearth_engram()
_KNOWLEDGE_GLOBS = ("Career/claude.md", "Areas/*/claude.md", "Projects/*/claude.md")
_MAX_SNIPPETS = 3
_SNIPPET_CHARS = 400


def _search_knowledge(query: str) -> list[tuple[str, str]]:
    """Paragraph-level keyword search across the Engram knowledge files.
    Returns up to ``_MAX_SNIPPETS`` of ``(source_label, snippet)``, best first.
    Fuzzy-tolerant per file vocabulary (difflib, cutoff 0.8) because the query
    arrives through STT -- 'Metta' must still find 'Meta'."""
    terms = [t for t in re.findall(r"[a-z0-9]+", query.lower()) if len(t) >= 3]
    if not terms:
        return []
    files: list[Path] = []
    for pattern in _KNOWLEDGE_GLOBS:
        files.extend(_ENGRAM_ROOT.glob(pattern))
    scored: list[tuple[int, str, str]] = []
    for f in files:
        if not f.is_file():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except Exception as exc:  # noqa: BLE001 - one unreadable file never breaks recall
            logger.warning("knowledge file unreadable %s: %s", f, exc)
            continue
        vocab = set(re.findall(r"[a-z0-9]+", text.lower()))
        expanded: set[str] = set()
        for t in terms:
            if t in vocab:
                expanded.add(t)
            else:
                expanded.update(difflib.get_close_matches(t, vocab, n=2, cutoff=0.8))
        if not expanded:
            continue
        # Career/claude.md -> "Career"; Projects/valinor/claude.md -> "valinor".
        label = f.parent.name if f.name == "claude.md" else f.stem
        for para in re.split(r"\n\s*\n", text):
            para_l = para.lower()
            score = sum(1 for t in expanded if t in para_l)
            if score:
                scored.append((score, label, para.strip()))
    scored.sort(key=lambda x: -x[0])
    return [(label, p[:_SNIPPET_CHARS]) for _, label, p in scored[:_MAX_SNIPPETS]]

# --- day-shaped recall ------------------------------------------------------
# "What did we do yesterday" is a DATE question, and lexical search cannot
# answer it: everything in the brain is dated in slug form (2026-08-18-...),
# so a query like "August 18, 2026" matches the words "August" and "2026" in
# unrelated notes and misses the day entirely (observed 2026-08-19: the top
# hit was an August 6 calendar-card session). When the query names a day,
# recall reads that day's shelf directly -- the daily review plus the day's
# session folders -- instead of gambling on tokenization.

_MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
    "december": 12,
}

_ISO_DAY_RE = re.compile(r"\b(\d{4})-(\d{2})-(\d{2})\b")
# "August 18[, 2026]" / "Aug 18th" -- the day number must not run into a year
# ("August 2026" alone names no day and must not parse as August 20).
_MONTH_DAY_RE = re.compile(
    r"\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?!\d)(?:,?\s+(\d{4}))?", re.I
)
_DAY_MONTH_RE = re.compile(
    r"\b(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})\b(?:,?\s+(\d{4}))?", re.I
)

_PERIOD_DAYS_RE = re.compile(r"\b(?:past|last)\s+(\d{1,2})\s+days?\b")

_MAX_REVIEW_CHARS = 1500
_MAX_DAY_SESSIONS = 8
_MAX_PERIOD_DAYS = 31
_MAX_PERIOD_SESSIONS = 20
_MAX_HIGHLIGHT_CHARS = 400


def _month_number(word: str) -> int | None:
    w = word.lower()
    for name, num in _MONTHS.items():
        if name.startswith(w) and len(w) >= 3:
            return num
    return None


def _resolve_day(year: int | None, month: int, day: int) -> str | None:
    """ISO date, defaulting a missing year to the most recent past occurrence."""
    try:
        if year is not None:
            return date(year, month, day).isoformat()
        today = date.today()
        candidate = date(today.year, month, day)
        if candidate > today:
            candidate = date(today.year - 1, month, day)
        return candidate.isoformat()
    except ValueError:
        return None


def parse_day(query: str) -> str | None:
    """The ISO day a query names, or None when it names no specific day."""
    q = (query or "").lower()
    m = _ISO_DAY_RE.search(q)
    if m:
        return _resolve_day(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    if "yesterday" in q:
        return (date.today() - timedelta(days=1)).isoformat()
    if "today" in q or "this morning" in q or "tonight" in q:
        return date.today().isoformat()
    m = _MONTH_DAY_RE.search(q)
    if m:
        month = _month_number(m.group(1))
        if month:
            year = int(m.group(3)) if m.group(3) else None
            return _resolve_day(year, month, int(m.group(2)))
    m = _DAY_MONTH_RE.search(q)
    if m:
        month = _month_number(m.group(2))
        if month:
            year = int(m.group(3)) if m.group(3) else None
            return _resolve_day(year, month, int(m.group(1)))
    return None


def parse_period(query: str) -> tuple[str, str] | None:
    """The (start, end) ISO window a query names, or None. Spoken periods are
    fuzzy: "last week" spans the previous Monday through yesterday, covering
    both the calendar week and "the last several days" readings without
    dragging in older weeks. Ported from Valinor (2026-08-20), the period
    extension of the 2026-08-19 day fast-path."""
    q = (query or "").lower()
    today = date.today()
    m = _PERIOD_DAYS_RE.search(q)
    if m:
        n = max(1, min(int(m.group(1)), _MAX_PERIOD_DAYS))
        return ((today - timedelta(days=n)).isoformat(), today.isoformat())
    monday = today - timedelta(days=today.weekday())
    if "last week" in q or "past week" in q:
        start = monday - timedelta(days=7)
        return (start.isoformat(), (today - timedelta(days=1)).isoformat())
    if "this week" in q:
        return (monday.isoformat(), today.isoformat())
    if "last month" in q or "past month" in q:
        last_prev = today.replace(day=1) - timedelta(days=1)
        return (last_prev.replace(day=1).isoformat(), last_prev.isoformat())
    if "this month" in q:
        return (today.replace(day=1).isoformat(), today.isoformat())
    if "recently" in q or "lately" in q or "these days" in q:
        return ((today - timedelta(days=7)).isoformat(), today.isoformat())
    return None


def _age_label(iso_day: str) -> str:
    """Plain-words age for a dated source, so the model never does date math:
    'today', 'yesterday', '5 days ago', '3 weeks ago', '2 months ago'."""
    try:
        d = date.fromisoformat(iso_day[:10])
    except ValueError:
        return ""
    days = (date.today() - d).days
    if days <= 0:
        return "today"
    if days == 1:
        return "yesterday"
    if days < 14:
        return f"{days} days ago"
    if days < 60:
        return f"{days // 7} weeks ago"
    return f"{days // 30} months ago"


def _date_from_source(source: str) -> str:
    """ISO date recoverable from an Engram-relative source path: the slug date
    for Thoughts/ and Reviews/, the file mtime for undated notes (projects,
    knowledge). Empty string when nothing is recoverable."""
    m = _ISO_DAY_RE.search(source or "")
    if m:
        return m.group(0)
    try:
        f = _ENGRAM_ROOT / source
        if f.is_file():
            import time as _time

            return _time.strftime("%Y-%m-%d", _time.localtime(f.stat().st_mtime))
    except OSError:
        pass
    return ""


_CARD_MAX_BLOCKS = 12  # generated_view renderers cap sections at 12
_CARD_BLOCK_CHARS = 420


def _journal_card(title: str, blocks: list[tuple[str, str]]) -> dict:
    """A generated_view card shaped like a journal page: each block renders as
    an eyebrow heading over its body (the `heading` field on text sections,
    2026-08-20 -- older clients ignore it and show the body alone). This is
    the screen half of a memory answer; the spoken `content` stays prose."""
    sections: list[dict] = []
    for heading, body in blocks[-_CARD_MAX_BLOCKS:]:
        sec: dict = {"kind": "text", "body": body[:_CARD_BLOCK_CHARS]}
        if heading:
            sec["heading"] = heading
        sections.append(sec)
    return {
        "version": 1,
        "type": "generated_view",
        "props": {"template": "brief", "title": title, "sections": sections},
    }


def _session_heading(folder: Path) -> str:
    """The session's own title line, from the diary or the chatlog."""
    for name in ("claude.md", "chatlog.md"):
        f = folder / name
        if not f.is_file():
            continue
        try:
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                s = line.strip()
                if s.startswith("#"):
                    return s.lstrip("# ").removeprefix("Chat Log:").strip()
                if s:
                    return s[:80]
        except OSError:
            continue
    return ""


def _recall_day(day: str) -> ToolResult:
    """Everything the brain holds for one day: the daily review (if written)
    and the day's sessions. Deterministic -- no ranking, no near-misses."""
    parts: list[str] = []
    review_path = _ENGRAM_ROOT / "Reviews" / "daily" / f"{day}.md"
    if review_path.is_file():
        try:
            text = review_path.read_text(encoding="utf-8", errors="replace").strip()
            parts.append(f"Daily review for {day}:\n{text[:_MAX_REVIEW_CHARS]}")
        except OSError as exc:
            logger.warning("day recall: review unreadable (%s)", exc)
    thoughts = _ENGRAM_ROOT / "Thoughts"
    sessions: list[str] = []
    if thoughts.is_dir():
        for folder in sorted(thoughts.iterdir()):
            if not (folder.is_dir() and folder.name.startswith(f"{day}-")):
                continue
            heading = _session_heading(folder)
            sessions.append(f"- {folder.name}" + (f": {heading}" if heading else ""))
            if len(sessions) >= _MAX_DAY_SESSIONS:
                break
    if sessions:
        parts.append(f"Sessions on {day}:\n" + "\n".join(sessions))
    if not parts:
        return ToolResult(
            content=(
                f"I have no records for {day} -- no review and no sessions. "
                "Say so plainly; do not reconstruct the day from memory."
            ),
            data={"day": day, "results": []},
        )
    logger.info("recall day fast-path: %s (%d session(s), review=%s)",
                day, len(sessions), review_path.is_file())
    blocks: list[tuple[str, str]] = []
    for part in parts:
        head, _, body = part.partition(":\n")
        blocks.append((head, body.strip() or part))
    return ToolResult(
        content=f"Here is what I have for {day}.\n\n" + "\n\n".join(parts),
        data={
            "day": day,
            "sessions": sessions,
            "review": review_path.is_file(),
            "ui_component": _journal_card(f"Journal · {day}", blocks),
        },
    )


def _extract_highlights(text: str) -> str:
    """The Highlights (or Review) section of a daily review, else the head
    with its title line stripped."""
    for name in ("Highlights", "Review"):
        m = re.search(rf"##\s*{name}\s*\n(.*?)(?=\n##\s|\Z)", text, re.S)
        if m:
            return m.group(1).strip()[:_MAX_HIGHLIGHT_CHARS]
    body = re.sub(r"^#\s.*\n+", "", text.strip())
    return body.strip()[:_MAX_HIGHLIGHT_CHARS]


def _recall_period(start: str, end: str) -> ToolResult:
    """The journal for a date window, day by day: each day's review highlights
    plus its session titles. The week-scale analog of _recall_day."""
    d0, d1 = date.fromisoformat(start), date.fromisoformat(end)
    if d1 < d0:
        d0, d1 = d1, d0
    if (d1 - d0).days + 1 > _MAX_PERIOD_DAYS:
        d0 = d1 - timedelta(days=_MAX_PERIOD_DAYS - 1)
    start, end = d0.isoformat(), d1.isoformat()

    # One pass over Thoughts/, bucketed by day prefix.
    by_day: dict[str, list[str]] = {}
    thoughts = _ENGRAM_ROOT / "Thoughts"
    if thoughts.is_dir():
        for folder in sorted(thoughts.iterdir()):
            if not folder.is_dir():
                continue
            iso = folder.name[:10]
            if not (start <= iso <= end and _ISO_DAY_RE.match(iso)):
                continue
            heading = _session_heading(folder)
            by_day.setdefault(iso, []).append(heading or folder.name)

    parts: list[str] = []
    blocks: list[tuple[str, str]] = []
    n_sessions = 0
    reviews = 0
    day = d0
    while day <= d1:
        iso = day.isoformat()
        day_lines: list[str] = []
        review = _ENGRAM_ROOT / "Reviews" / "daily" / f"{iso}.md"
        if review.is_file():
            try:
                text = review.read_text(encoding="utf-8", errors="replace")
                day_lines.append(_extract_highlights(text))
                reviews += 1
            except OSError as exc:
                logger.warning("period recall: review unreadable (%s)", exc)
        titles = by_day.get(iso, [])
        if titles and n_sessions < _MAX_PERIOD_SESSIONS:
            keep = titles[: _MAX_PERIOD_SESSIONS - n_sessions]
            n_sessions += len(keep)
            day_lines.append("Sessions: " + "; ".join(keep))
        if day_lines:
            parts.append(f"{iso} ({day.strftime('%A')}):\n" + "\n".join(day_lines))
            blocks.append((f"{day.strftime('%A')} · {iso}", "\n".join(day_lines)))
        day += timedelta(days=1)

    if not parts:
        return ToolResult(
            content=(
                f"I have no records between {start} and {end} -- no reviews and "
                "no sessions. Say so plainly; do not reconstruct the period "
                "from memory."
            ),
            data={"start": start, "end": end, "results": []},
        )
    logger.info("recall period fast-path: %s..%s (%d day(s), %d session(s), %d review(s))",
                start, end, len(parts), n_sessions, reviews)
    return ToolResult(
        content=(
            f"The journal from {start} to {end}. Answer ONLY from this record; "
            "older memories are not evidence of work in this period.\n\n"
            + "\n\n".join(parts)
        ),
        data={
            "start": start,
            "end": end,
            "days": len(parts),
            "sessions": n_sessions,
            "ui_component": _journal_card(f"Journal · {start} to {end}", blocks),
        },
    )


_brain_sync = None
_import_failed = False


def _ensure_brain_sync():
    """Lazily import the shared Engram helpers. Returns the module or None."""
    global _brain_sync, _import_failed
    if _brain_sync is not None:
        return _brain_sync
    if _import_failed:
        return None
    try:
        from memory import brain_sync  # type: ignore
    except Exception as exc:  # noqa: BLE001
        logger.warning("Engram brain_sync unavailable; memory tools degraded: %s", exc)
        _import_failed = True
        return None
    _brain_sync = brain_sync
    return brain_sync


async def remember(args: dict) -> ToolResult:
    """args: {fact: str}. Store a durable fact about the operator in Engram's
    shared operator-facts file. Routed through the engram-mcp seam (the same
    write contract + single-writer lock every client uses); falls back to the
    direct brain_sync write if the package is unavailable."""
    fact = str(args.get("fact") or args.get("text") or "").strip()
    if not fact:
        return ToolResult.error("there was nothing to remember -- tell me the fact.")
    short = fact if len(fact) <= 80 else fact[:77] + "..."

    from ...memory.service import get_engram_service

    svc = get_engram_service()
    if svc.available():
        result = await svc.promote_fact(fact, source="valar-voice")
        if isinstance(result, dict) and result.get("ok", False):
            return ToolResult(
                content=f"Got it -- I'll remember that {short}", data={"stored": fact}
            )
        logger.warning("promote_fact degraded; falling back to brain_sync")

    bs = _ensure_brain_sync()
    if bs is None:
        return ToolResult.error("my long-term memory is not available right now.")
    try:
        result = bs.add_operator_fact(fact, source="valar-voice")  # type: ignore[union-attr]
    except Exception as exc:  # noqa: BLE001
        logger.error("remember failed: %s", exc)
        return ToolResult.error("I could not save that to memory.")
    if isinstance(result, dict) and not result.get("ok", True):
        return ToolResult.error(f"I could not save that: {result.get('error', 'unknown error')}.")
    return ToolResult(content=f"Got it -- I'll remember that {short}", data={"stored": fact})


def _recall_house(args: dict) -> ToolResult:
    """args: {query: str}. Search the operator's FULL long-term memory.

    Primary path (2026-06-06): the engram-mcp seam's four-scope search --
    saved facts + session thoughts (diaries) + project notes + background
    knowledge (Career/Areas, fuzzy STT-tolerant). The same search every other
    client gets. Falls back to the legacy two-tier (brain_sync facts + the
    local knowledge grep) when the package is unavailable."""
    query = str(args.get("query") or args.get("text") or "").strip()
    # Period fast-path (2026-08-20): "last week" names no single day; answer
    # it from the window's journal before trying the day path.
    period = parse_period(query)
    if period:
        try:
            return _recall_period(*period)
        except Exception as exc:  # noqa: BLE001 - fall through to search
            logger.warning("period recall failed (%s); falling back to search", exc)
    # Day fast-path (2026-08-19): a query that names a day is answered from
    # that day's shelf directly. See the block comment above parse_day.
    day = parse_day(query)
    if day:
        try:
            return _recall_day(day)
        except Exception as exc:  # noqa: BLE001 - fall through to search
            logger.warning("day recall failed (%s); falling back to search", exc)
    # Intent scoping (2026-06-07): lexical ranking cannot tell "my time at
    # Apple" (career intent) from Apple Vision Pro project notes -- the MODEL
    # can, so the tool exposes the intent and we narrow the Engram scopes.
    intent = str(args.get("scope") or "all").strip().lower()
    scope_map = {
        "background": ["facts", "knowledge"],
        "personal_projects": ["projects"],
        "projects": ["projects"],  # legacy alias
        "sessions": ["thoughts", "reviews"],
    }
    scopes = scope_map.get(intent)  # None -> the service default

    from ...memory.service import get_engram_service

    svc = get_engram_service()
    if svc.available() and query:
        results = svc.search(query, scope=scopes, limit=10)
        if not results:
            return ToolResult(
                content=(
                    f"I don't have anything stored about '{query}'. "
                    "Say so plainly; do not invent a memory."
                ),
                data={"results": []},
            )
        # Context discipline (2026-06-07): the MODEL sees only the top few
        # snippets (smaller grounded context = shorter spoken answers + less
        # empty-answer pressure); the FULL result set rides data for the
        # composer's cards. A caller with its own fresh window (the Selene
        # subagent) may ask for more via max_results (capped at 10).
        try:
            max_results = max(1, min(int(args.get("max_results") or 5), 10))
        except (TypeError, ValueError):
            max_results = 5
        parts: list[str] = []
        blocks: list[tuple[str, str]] = []
        top = results[:max_results]
        facts = [r for r in top if r.get("scope") == "facts"]
        if facts:
            fact_line = "; ".join(r.get("snippet", "") for r in facts)
            parts.append("Saved facts: " + fact_line)
            blocks.append(("Saved facts", fact_line))
        for r in top:
            scope = r.get("scope")
            # Every hit is dated (2026-08-20): a snippet with no age reads as
            # current, which is how months-old project notes get presented as
            # recent work. Recover the date from the slug or the file mtime
            # and say it in plain words so the model never does date math.
            when_iso = str(r.get("date") or "") or _date_from_source(
                str(r.get("source") or "")
            )
            age = _age_label(when_iso) if when_iso else ""
            when = f" ({when_iso}, {age})" if age else (f" ({when_iso})" if when_iso else "")
            snippet = r.get("snippet", "")
            if scope == "thoughts":
                parts.append(f"From a past session{when}: {snippet}")
                blocks.append((f"Past session · {age or when_iso or '?'}", snippet))
            elif scope == "reviews":
                parts.append(
                    f"From a daily review ({r.get('source', '?')}{when}): {snippet}"
                )
                blocks.append((f"Daily review · {age or when_iso or '?'}", snippet))
            elif scope in ("projects", "knowledge"):
                stamp = f", last updated {when_iso}, {age}" if age else ""
                parts.append(
                    f"From my notes ({r.get('source', '?')}{stamp}): {snippet}"
                )
                label = str(r.get("source", "?"))
                blocks.append((f"{label} · {age}" if age else label, snippet))
        return ToolResult(
            content="Here is what I remember.\n\n" + "\n\n".join(parts),
            data={
                "results": results,
                "ui_component": _journal_card("From memory", blocks),
            },
        )

    bs = _ensure_brain_sync()
    if bs is None:
        return ToolResult.error("my long-term memory is not available right now.")
    try:
        if query:
            matches = bs.search_operator_facts(query)  # type: ignore[union-attr]
        else:
            # No query -> surface the most recent facts (load_operator_facts
            # returns a pre-rendered block; pass it through as-is).
            block = bs.load_operator_facts()  # type: ignore[union-attr]
            if not block:
                return ToolResult(content="I don't have anything stored yet.", data={"facts": []})
            return ToolResult(content=block, data={"facts": [block]})
    except Exception as exc:  # noqa: BLE001
        logger.error("recall failed: %s", exc)
        return ToolResult.error("I could not search my memory just now.")
    # Knowledge tier: the background notes (career, projects) -- the saved-facts
    # store is tiny and explicit; the operator's actual story lives here.
    notes: list[tuple[str, str]] = []
    try:
        notes = _search_knowledge(query)
    except Exception as exc:  # noqa: BLE001 - the facts tier still stands
        logger.warning("knowledge search failed: %s", exc)
    if not matches and not notes:
        msg = f"I don't have anything stored about '{query}'." if query else "I don't have anything stored yet."
        return ToolResult(content=msg, data={"facts": []})
    parts = []
    if matches:
        parts.append("Saved facts: " + "; ".join(matches))
    for label, snippet in notes:
        parts.append(f"From my {label} notes: {snippet}")
    return ToolResult(
        content="Here is what I remember.\n\n" + "\n\n".join(parts),
        data={"facts": matches, "notes": [s for _, s in notes]},
    )


# --- correcting and searching what was kept -------------------------------


def _facts_path() -> Path | None:
    """The shared operator-facts file, or None when memory is unavailable."""
    bs = _ensure_brain_sync()
    if bs is None:
        return None
    try:
        return bs._operator_facts_path()  # type: ignore[union-attr]
    except Exception:  # noqa: BLE001
        return None


def forget(args: dict) -> ToolResult:
    """args: {fact: str, replace_with?: str}. Remove or correct one stored fact.

    ``remember`` wrote and nothing unwrote, so a fact that was wrong when it
    was said stayed wrong until someone opened the file by hand. This is the
    other direction.

    It refuses to guess. One match is removed; several are listed back so the
    operator can say which, because deleting the wrong memory is worse than
    asking a second question.
    """
    query = str((args or {}).get("fact") or (args or {}).get("query") or "").strip()
    replacement = str((args or {}).get("replace_with") or "").strip()
    if len(query) < 3:
        return ToolResult.error("Tell me which fact to forget, in a few words.")

    path = _facts_path()
    if path is None or not path.is_file():
        return ToolResult.error("There are no stored facts to forget.")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return ToolResult.error(f"Could not read the facts file: {exc}")

    needle = query.lower()
    hits = [
        i
        for i, ln in enumerate(lines)
        if ln.strip().startswith("- ") and needle in ln.lower()
    ]
    if not hits:
        return ToolResult.error(
            f"Nothing stored matches {query!r}. Say so plainly rather than "
            "claiming to have forgotten something."
        )
    if len(hits) > 1:
        shown = "; ".join(lines[i].strip()[2:][:80] for i in hits[:5])
        return ToolResult.error(
            f"{len(hits)} stored facts match {query!r}: {shown}. "
            "Ask which one before removing anything."
        )

    idx = hits[0]
    removed = lines[idx].strip()[2:]
    if replacement:
        lines[idx] = f"- {replacement}"
    else:
        del lines[idx]
    try:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    except OSError as exc:
        return ToolResult.error(f"Could not update the facts file: {exc}")

    logger.info("forget: %s %r", "replaced" if replacement else "removed", removed[:60])
    return ToolResult(
        content=(
            (f"Corrected: {removed[:100]} -> {replacement[:100]}" if replacement
             else f"Forgotten: {removed[:120]}")
            + "\nConfirm briefly in your own words."
        ),
        data={"removed": removed, "replaced_with": replacement},
    )


_PERIOD_PHRASES = (
    "last week", "past week", "this week", "last month", "past month",
    "this month", "yesterday", "today", "recently", "lately",
)


def search_journal(args: dict) -> ToolResult:
    """args: {query: str, limit?: int, since?: str, until?: str}. Full text
    across past conversations, optionally restricted to a date window.

    ``recall`` searches the memory layer's own index; this reads the diaries
    themselves, which is what answers "when did we talk about X" with a date
    and a session to open. A window comes from explicit since/until args or
    from period words in the query itself ("last week", "yesterday"); a
    window with no remaining search words returns the period's journal.
    """
    query = str((args or {}).get("query") or "").strip()
    limit = int((args or {}).get("limit") or 8)

    # Date window: explicit args win; else period/day words in the query.
    since = str((args or {}).get("since") or "").strip()
    until = str((args or {}).get("until") or "").strip()
    window: tuple[str, str] | None = None
    if since or until:
        window = (since or "0000-01-01", until or date.today().isoformat())
    else:
        window = parse_period(query)
        if window is None:
            d = parse_day(query)
            if d:
                window = (d, d)

    # Period words are window, not needle -- "visionOS last week" must search
    # for "visionOS" inside the window, not for the words "last week".
    needle_text = query.lower()
    for ph in _PERIOD_PHRASES:
        needle_text = needle_text.replace(ph, " ")
    needle_text = " ".join(needle_text.split())
    if window and len(needle_text) < 2:
        try:
            return _recall_period(*window)
        except Exception as exc:  # noqa: BLE001
            logger.warning("period journal failed (%s)", exc)
    if len(needle_text) < 2:
        return ToolResult.error("search_journal needs at least two characters.")
    query = needle_text

    try:
        from ...memory.journal_sync import engram_root
    except Exception:  # noqa: BLE001
        return ToolResult.error("The journal is not available.")
    root = engram_root()
    if root is None:
        return ToolResult.error("There is no second brain connected to search.")

    needle = query.lower()
    hits: list[dict] = []
    thoughts = root / "Thoughts"
    if not thoughts.is_dir():
        return ToolResult.error("The journal has no sessions yet.")
    try:
        days = sorted((d for d in thoughts.iterdir() if d.is_dir()), reverse=True)
    except OSError as exc:
        return ToolResult.error(f"Could not read the journal: {exc}")

    for d in days:
        if len(hits) >= max(1, min(limit, 20)):
            break
        if window and not (window[0] <= d.name[:10] <= window[1]):
            continue
        for name in ("claude.md", "chatlog.md"):
            f = d / name
            if not f.is_file():
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            at = text.lower().find(needle)
            if at < 0:
                continue
            start = max(0, at - 70)
            snippet = " ".join(text[start : at + len(query) + 110].split())
            hits.append({"slug": d.name, "where": name, "snippet": snippet})
            break

    if not hits:
        scope_note = f" between {window[0]} and {window[1]}" if window else ""
        return ToolResult(
            content=(
                f"No past conversation{scope_note} mentions {query!r}. Say so "
                "plainly; do not reconstruct one from memory."
            ),
            data={"query": query, "hits": []},
        )
    lines = [f"Journal matches for {query!r}: {len(hits)}"]
    blocks: list[tuple[str, str]] = []
    for h in hits:
        age = _age_label(h["slug"][:10])
        stamp = f" ({age})" if age else ""
        lines.append(f"- {h['slug']}{stamp}: {h['snippet'][:180]}")
        # "2026-08-19-visionos-client-and-..." -> "Visionos client and ..."
        pretty = h["slug"][11:].replace("-", " ").strip().capitalize() or h["slug"][:10]
        heading = " · ".join(p for p in (pretty, h["slug"][:10], age) if p)
        # The card body drops the chatlog's own markdown scaffolding
        # ("# Chat Log:", "### User ()", "---"); the heading already names it.
        snip = " ".join(re.sub(r"#+|---", " ", h["snippet"][:220]).split())
        blocks.append((heading, snip))
    logger.info("search_journal %r -> %d", query, len(hits))
    return ToolResult(
        content="\n".join(lines),
        data={
            "query": query,
            "hits": hits,
            "ui_component": _journal_card("From the journal", blocks),
        },
    )

# --------------------------------------------------------------- self scope
# Spec section 4 of
# docs/superpowers/specs/2026-09-02-persona-private-memory-design.md: a
# persona's own record answers first, deterministically and cheaply, and
# only an explicit scope reaches the house's shared shelf. There is no
# argument that reaches ANOTHER persona's record; the root comes from the
# acting contextvar, never from a name.


def _reconstruct(root: Path, label: str, rows: list[dict]) -> Path:
    """The paper trail: a day or a session written out as a file to point at."""
    from ...memory import persona_memory as pm

    out = Path(root) / pm.RECON_DIRNAME / f"{label}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# {label}", ""]
    for r in rows:
        when = str(r.get("ts") or "")[11:16]
        origin = str(r.get("origin") or "")
        client = str(r.get("client") or "")
        lines.append(f"## {when} {origin or client}".rstrip())
        if r.get("question"):
            lines.append(f"Asked: {r['question']}")
        touched = r.get("touched") or []
        if touched:
            lines.append("Touched: " + "; ".join(str(t) for t in touched))
        if r.get("dispatches"):
            lines.append("Asked of others: " + ", ".join(r["dispatches"]))
        if r.get("answer"):
            lines.append(f"Answered: {r['answer']}")
        lines.append("")
    out.write_text("\n".join(lines), encoding="utf-8")
    return out


def _rows_line(r: dict) -> str:
    when = str(r.get("ts") or r.get("as_of") or "")
    touched = ", ".join(str(t) for t in (r.get("touched") or []))
    question = r.get("question") or r.get("text") or ""
    answer = r.get("answer") or ""
    bits = [when[11:16] or when[:10], question]
    if touched:
        bits.append(f"[{touched}]")
    if answer:
        bits.append(f"-> {answer}")
    return " ".join(b for b in bits if b)


def _recall_self(act, day: str, session: str, query: str, reconstruct: bool, limit: int) -> ToolResult:
    from ...memory import persona_archive as pa

    root = Path(act.memory_dir)
    if session:
        rows = pa.query_session(root, session)
        label = session
    elif day:
        rows = pa.query_day(root, day)
        label = day
    else:
        rows = pa.search(root, query, limit=limit)
        label = query.replace(" ", "-")[:40] or "search"

    if not rows:
        what = session or day or f"'{query}'"
        return ToolResult(
            content=f"I have no record of {what} in my own memory.",
            data={"rows": [], "scope": "self"},
        )

    head_rows = rows[:limit]
    body = "\n".join(f"- {_rows_line(r)}" for r in head_rows)
    more = f"\n({len(rows) - len(head_rows)} more.)" if len(rows) > len(head_rows) else ""
    as_of = str(rows[0].get("day") or rows[0].get("ts") or "")[:10]
    age = _age_label(as_of) if as_of else ""
    header = f"My own record of {label}" + (f", {age}" if age else "") + ":"

    data: dict = {"rows": head_rows, "scope": "self", "as_of": as_of}
    if reconstruct:
        try:
            path = _reconstruct(root, label, rows)
            data["path"] = str(path)
            more += f"\nWritten out in full at {path}."
        except Exception as exc:  # noqa: BLE001 - the answer stands without the file
            logger.warning("reconstruct failed: %s", exc)
    return ToolResult(content=f"{header}\n{body}{more}", data=data)


def recall(args: dict) -> ToolResult:
    """Your own record first; the house's shared record only when asked for.

    scope self (the default) reads the persona's own log, index and archive
    deterministically: a day, a session id, or an FTS query over its own
    turns and notes. scope house is the Engram search every client already
    had, labelled as the house's record rather than the persona's memory.
    Outside a turn there is no acting persona, so the house scope is all
    there is to answer with.
    """
    from ...memory.acting import current_acting

    scope = str(args.get("scope") or "self").strip().lower()
    query = str(args.get("query") or args.get("text") or "").strip()
    # Anything but "self" is the house. The intent values the shared search
    # has always taken (background, personal_projects, sessions, all) are
    # house scopes too, and _recall_house reads them from args unchanged, so
    # a model that learned the old vocabulary still lands where it meant to.
    if scope != "self":
        return _recall_house(args)

    act = current_acting()
    if act is None:
        return _recall_house(args)

    day = str(args.get("day") or "").strip()
    session = str(args.get("session") or "").strip()
    if not day and not session and query:
        day = parse_day(query) or ""
    if not day and not session and not query:
        try:
            return ToolResult.error(
                "Tell me a day, a session, or something to search my memory for.",
                reason="bad_input",
            )
        except TypeError:  # Hearth's ToolResult has no reason field yet
            return ToolResult.error(
                "Tell me a day, a session, or something to search my memory for."
            )
    try:
        limit = max(1, min(int(args.get("max_results") or 8), 20))
    except (TypeError, ValueError):
        limit = 8
    try:
        result = _recall_self(act, day, session, query, bool(args.get("reconstruct")), limit)
    except Exception as exc:  # noqa: BLE001 - the house scope is the fallback
        logger.warning("self recall failed (%s); falling back to the house", exc)
        return _recall_house(args)
    # A period question ("last week") is the house's shelf, not one log file.
    if not result.data.get("rows") and query and parse_period(query):
        return _recall_house(args)
    return result
