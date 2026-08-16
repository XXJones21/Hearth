"""Read-only Journal API over the Engram layer.

Serves the Hearth client's Journal surface (Selene's room): session diaries,
Selene's consolidation Reviews, and operator facts. Strictly read-only --
writes stay with brain_sync / engram-mcp (the server remains Engram's only
writer). Diary format is the one session_persist writes: a metadata bullet
block (Date / Personality / Related Project / Tags / Session ID) followed by
Summary / Key Decisions / Open Questions / Action Items sections.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

from fastapi import FastAPI, HTTPException

from ..config.settings import HearthConfigError, hearth_engram

logger = logging.getLogger("valar.gateway.journal")

_META_RE = re.compile(r"^\s*-\s+\*\*(?P<key>[^:*]+):\*\*\s*(?P<value>.*)$")
_DATED_DIR_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-")
_H1_RE = re.compile(r"^#\s+(.+)$")
_LIFE_DIRS = ("Career", "Areas", "Resources", "Research", "Ideas", "Archive")


def _engram_root(repo_root: Path) -> Path | None:
    """The memory tree, or None when it is not configured.

    There is no candidate list. Searching for a memory tree is how a fresh
    install silently adopts whichever brain happens to be on the machine and
    presents it as the new user's, so an unset HEARTH_ENGRAM is reported as
    a named failure rather than resolved by looking around. A configured but
    empty tree is a normal new install and returns empty pages, not an error.
    """
    try:
        return hearth_engram()
    except HearthConfigError as exc:
        logger.warning("journal unavailable: %s", exc)
        return None


def _parse_diary(text: str) -> dict:
    """Parse a session diary claude.md into structured metadata + sections."""
    meta: dict[str, str] = {}
    sections: dict[str, list[str]] = {}
    title = ""
    current: str | None = None
    for line in text.splitlines():
        if line.startswith("# ") and not title:
            title = line[2:].strip()
            continue
        if line.startswith("## "):
            current = line[3:].strip().lower()
            sections.setdefault(current, [])
            continue
        m = _META_RE.match(line)
        if m and current is None:
            meta[m.group("key").strip().lower()] = m.group("value").strip()
            continue
        if current is not None and line.strip():
            sections[current].append(line.rstrip())

    def _bullets(name: str) -> list[str]:
        items = [
            re.sub(r"^\s*-\s*", "", ln).strip()
            for ln in sections.get(name, [])
            if ln.strip().startswith("-")
        ]
        return [i for i in items if i and i.lower() != "none recorded"]

    return {
        "title": title,
        "date": meta.get("date", ""),
        "persona": meta.get("personality", ""),
        "project": "" if meta.get("related project", "") in ("none", "") else meta["related project"],
        "tags": [t.strip() for t in meta.get("tags", "").split(",") if t.strip()],
        "session_id": meta.get("session id", ""),
        "summary": "\n".join(sections.get("summary", [])).strip(),
        "decisions": _bullets("key decisions"),
        "questions": _bullets("open questions"),
        "actions": _bullets("action items"),
    }


def _entry_title(path: Path) -> str:
    """A human title for a library entry: the file's own H1, else its name."""
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            for _ in range(5):
                line = fh.readline()
                if not line:
                    break
                m = _H1_RE.match(line)
                if m:
                    return re.sub(r"\s*--.*$", "", m.group(1)).strip()
    except OSError:
        pass
    return " ".join(w.capitalize() for w in path.stem.split("-") if w)


def _first_para(path: Path, max_chars: int = 300) -> str:
    """First prose paragraph of a markdown file, headings/bullets skipped."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[:40]
    except OSError:
        return ""
    buf: list[str] = []
    started = False
    for line in lines:
        if line.startswith("#") or not line.strip():
            if started:
                break
            continue
        if not started and line.lstrip()[:1] in ("-", "|", ">", "*"):
            continue
        started = True
        buf.append(line.strip())
    text = " ".join(buf)
    return text[:max_chars].rstrip() + ("..." if len(text) > max_chars else "")


def _dir_book(d: Path, curated: dict[str, str]) -> dict:
    files = sorted(d.rglob("*.md"), key=lambda f: f.stat().st_mtime, reverse=True)
    entries = [
        {
            "t": _entry_title(f),
            "d": __import__("datetime").datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d"),
            "s": _first_para(f, 220),
        }
        for f in files
    ]
    claude_md = d / "claude.md"
    idx_md = d / "_index.md"
    summary = curated.get(d.name) or (
        _first_para(claude_md, 380) if claude_md.is_file()
        else _first_para(idx_md, 380) if idx_md.is_file()
        else ""
    )
    return {"title": d.name, "pages": len(files), "summary": summary, "entries": entries}


def _curated_pages(repo_root: Path) -> dict[str, str]:
    """Selene's authored book pages. Product data, shipped with the harness.
    It spent a while inside a pitch deck's mockup folder, which is the reason
    it was the item most likely to be lost in the move."""
    path = Path(__file__).resolve().parent.parent / "data" / "selene-pages.json"
    try:
        import json

        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return {}


def _session_dirs(root: Path) -> list[Path]:
    thoughts = root / "Thoughts"
    if not thoughts.is_dir():
        return []
    dirs = [d for d in thoughts.iterdir() if d.is_dir() and _DATED_DIR_RE.match(d.name)]
    return sorted(dirs, key=lambda d: d.name, reverse=True)


def _chatlog_list_fields(chatlog: Path) -> tuple[str, str]:
    """Title and first-user-line preview from a chatlog.md."""
    title = ""
    summary = ""
    try:
        lines = chatlog.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return "", ""
    for i, line in enumerate(lines):
        if line.startswith("# ") and not title:
            title = line[2:].strip()
            if title.lower().startswith("chat log:"):
                title = title[9:].strip()
            continue
        if line.startswith("### User"):
            body: list[str] = []
            for ln in lines[i + 1 :]:
                if ln.startswith("### ") or ln.strip() == "---":
                    break
                if ln.strip():
                    body.append(ln.strip())
            summary = " ".join(body)[:400]
            break
    return title, summary


def _empty_session_entry(slug: str, title: str, summary: str, date: str) -> dict:
    return {
        "title": title or "Untitled",
        "date": date,
        "persona": "",
        "project": "",
        "tags": [],
        "session_id": "",
        "summary": summary,
        "decisions": [],
        "questions": [],
        "actions": [],
        "slug": slug,
    }


def _line_title(text: str) -> str:
    """First-line title from a user utterance or summary, Operator: stripped."""
    t = " ".join((text or "").split())
    low = t.lower()
    for prefix in ("operator:", "user:"):
        if low.startswith(prefix):
            t = t[len(prefix) :].strip()
            break
    if len(t) > 56:
        t = t[:56].rsplit(" ", 1)[0] or t[:56]
    return t


def _prefer_title(title: str, *fallbacks: str) -> str:
    """Keep a real title; replace the summarizer's Voice session fallback."""
    raw = (title or "").strip()
    if raw.lower().startswith("chat log:"):
        raw = raw[9:].strip()
    generic = raw.lower() in ("", "voice session", "untitled", "untitled session")
    if not generic:
        return raw
    for fb in fallbacks:
        cand = _line_title(fb)
        if cand:
            return cand
    return raw or "Untitled"


def _session_entry_from_dir(d: Path) -> dict | None:
    """List row for a Thoughts slug: diary if present, else chatlog-only."""
    diary = d / "claude.md"
    chatlog = d / "chatlog.md"
    date = d.name[:10] if _DATED_DIR_RE.match(d.name) else ""
    if diary.is_file():
        try:
            entry = _parse_diary(diary.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            return None
        entry["slug"] = d.name
        if not entry.get("date"):
            entry["date"] = date
        entry["has_transcript"] = chatlog.is_file()
        entry["summary"] = str(entry.get("summary") or "")[:400]
        chatlog_user = ""
        if chatlog.is_file():
            _, chatlog_user = _chatlog_list_fields(chatlog)
        entry["title"] = _prefer_title(
            str(entry.get("title") or ""),
            chatlog_user,
            str(entry.get("summary") or ""),
        )
        return entry
    if chatlog.is_file():
        title, summary = _chatlog_list_fields(chatlog)
        entry = _empty_session_entry(d.name, title, summary, date)
        entry["has_transcript"] = True
        entry["title"] = _prefer_title(title, summary)
        return entry
    return None


def register(app: FastAPI, repo_root: Path) -> None:
    @app.get("/journal/sessions")
    def journal_sessions(persona: str = "", project: str = "", limit: int = 60):
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        out = []
        for d in _session_dirs(root):
            entry = _session_entry_from_dir(d)
            if entry is None:
                continue
            if persona and str(entry.get("persona") or "").lower() != persona.lower():
                continue
            if project and str(entry.get("project") or "").lower() != project.lower():
                continue
            out.append(entry)
            if len(out) >= max(1, min(limit, 200)):
                break
        return {"sessions": out}

    @app.get("/journal/session/{slug}")
    def journal_session(slug: str, transcript: int = 0):
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        if "/" in slug or "\\" in slug or ".." in slug:
            raise HTTPException(400, "bad slug")
        d = root / "Thoughts" / slug
        entry = _session_entry_from_dir(d)
        if entry is None:
            raise HTTPException(404, "no such session")
        chatlog = d / "chatlog.md"
        if transcript and chatlog.is_file():
            entry["transcript"] = chatlog.read_text(encoding="utf-8", errors="replace")[:200_000]
        return entry

    @app.get("/journal/reviews")
    def journal_reviews(limit: int = 14):
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        daily = root / "Reviews" / "daily"
        out = []
        if daily.is_dir():
            for f in sorted(daily.glob("*.md"), reverse=True)[: max(1, min(limit, 60))]:
                try:
                    out.append({"date": f.stem, "body": f.read_text(encoding="utf-8", errors="replace")})
                except OSError:
                    continue
        return {"reviews": out}

    @app.get("/journal/facts")
    def journal_facts():
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        facts = root / "operator-facts.md"
        body = facts.read_text(encoding="utf-8", errors="replace") if facts.is_file() else ""
        return {"body": body}

    @app.get("/journal/shelf")
    def journal_shelf():
        """The library's shelves: project + life books with curated summaries
        and titled entries. The living volumes (Journal/facts/Ledger) come
        from the existing endpoints; this serves everything else."""
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        curated = _curated_pages(repo_root)
        projects_dir = root / "Projects"
        projects = []
        if projects_dir.is_dir():
            projects = [_dir_book(d, curated) for d in sorted(projects_dir.iterdir()) if d.is_dir()]
        life = [
            _dir_book(root / name, curated)
            for name in _LIFE_DIRS
            if (root / name).is_dir()
        ]
        return {"projects": projects, "life": life}

    @app.get("/journal/search")
    def journal_search(q: str, limit: int = 30):
        root = _engram_root(repo_root)
        if root is None:
            raise HTTPException(503, "Engram not available")
        needle = q.strip().lower()
        if len(needle) < 2:
            return {"results": []}
        results = []
        for d in _session_dirs(root):
            diary = d / "claude.md"
            if not diary.is_file():
                continue
            try:
                text = diary.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            idx = text.lower().find(needle)
            if idx < 0:
                continue
            start = max(0, idx - 80)
            snippet = text[start : idx + len(needle) + 80].replace("\n", " ").strip()
            results.append({"slug": d.name, "snippet": snippet})
            if len(results) >= max(1, min(limit, 100)):
                break
        return {"results": results}

    logger.info("journal API registered (read-only Engram surface)")
