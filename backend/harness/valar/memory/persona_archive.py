"""The persona's archive: the week's loose files, consolidated.

Spec section 1 of docs/superpowers/specs/2026-09-02-persona-private-memory-design.md.
Files are the live week; this database is where they go after seven days,
so a persona folder never holds more than a week of paper. Every row
carries as_of. Notes that the persona prunes from its files are retired
here, never lost. Same rule as the files: no function here takes a persona
name, only the root the caller resolved.
"""

from __future__ import annotations

import json
import logging
import sqlite3
from datetime import date, timedelta
from pathlib import Path

from . import persona_memory as pm

logger = logging.getLogger("valar.memory.persona_archive")

DB_FILE = "mind.sqlite"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY, day TEXT NOT NULL, client TEXT, origin TEXT,
    title TEXT, turns INTEGER, topic TEXT, as_of TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS turns (
    rowid INTEGER PRIMARY KEY, ts TEXT NOT NULL, day TEXT NOT NULL, session TEXT,
    origin TEXT, client TEXT, question TEXT, tools TEXT, touched TEXT,
    answer TEXT, dispatches TEXT, as_of TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS turns_day ON turns(day);
CREATE INDEX IF NOT EXISTS turns_session ON turns(session);
CREATE TABLE IF NOT EXISTS notes (
    rowid INTEGER PRIMARY KEY, kind TEXT NOT NULL, text TEXT NOT NULL,
    as_of TEXT NOT NULL, retired_at TEXT, volatility TEXT DEFAULT 'slow'
);
CREATE TABLE IF NOT EXISTS reports (
    day TEXT PRIMARY KEY, text TEXT NOT NULL, as_of TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS turns_fts USING fts5(
    question, answer, touched, content='turns', content_rowid='rowid'
);
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    text, content='notes', content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS turns_ai AFTER INSERT ON turns BEGIN
    INSERT INTO turns_fts(rowid, question, answer, touched)
    VALUES (new.rowid, new.question, new.answer, new.touched);
END;
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
    INSERT INTO notes_fts(rowid, text) VALUES (new.rowid, new.text);
END;
"""


def open_db(root: Path) -> sqlite3.Connection:
    root = pm.scaffold(Path(root))
    conn = sqlite3.connect(root / DB_FILE)
    conn.row_factory = sqlite3.Row
    conn.executescript(_SCHEMA)
    return conn


def _row(r: sqlite3.Row) -> dict:
    d = dict(r)
    for k in ("tools", "touched", "dispatches"):
        if isinstance(d.get(k), str):
            try:
                d[k] = json.loads(d[k])
            except json.JSONDecodeError:
                d[k] = []
    return d


def consolidate(root: Path, older_than_days: int = 7, today: date | None = None) -> dict:
    """Move log files and index rows older than the window into the database.

    Idempotent and cheap when nothing is old enough. The log files it absorbs
    are deleted; sessions.jsonl is rewritten compact with only the rows still
    inside the window.
    """
    root = pm.scaffold(Path(root))
    cutoff = ((today or date.today()) - timedelta(days=older_than_days)).isoformat()
    moved_turns = 0
    days: list[str] = []
    conn = open_db(root)
    try:
        for path in sorted((root / pm.LOG_DIRNAME).glob("*.jsonl")):
            day = path.stem
            if day >= cutoff:
                continue
            for e in pm.read_log(root, day):
                conn.execute(
                    "INSERT INTO turns (ts, day, session, origin, client, question, tools,"
                    " touched, answer, dispatches, as_of) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (
                        e.get("ts", ""), day, e.get("session", ""), e.get("origin", ""),
                        e.get("client", ""), e.get("question", ""),
                        json.dumps(e.get("tools") or []), json.dumps(e.get("touched") or []),
                        e.get("answer", ""), json.dumps(e.get("dispatches") or []),
                        (e.get("ts", "") or "")[:10] or day,
                    ),
                )
                moved_turns += 1
            path.unlink()
            days.append(day)
        keep: list[dict] = []
        moved_sessions = 0
        for row in pm.read_sessions(root):
            if str(row.get("day", "")) >= cutoff:
                keep.append(row)
                continue
            conn.execute(
                "INSERT OR REPLACE INTO sessions (id, day, client, origin, title, turns, topic, as_of)"
                " VALUES (?,?,?,?,?,?,?,?)",
                (
                    row["id"], row.get("day", ""), row.get("client", ""), row.get("origin", ""),
                    row.get("title", ""), int(row.get("turns") or 0), row.get("topic", ""),
                    row.get("updated") or row.get("day", ""),
                ),
            )
            moved_sessions += 1
        conn.commit()
    finally:
        conn.close()
    tmp = root / (pm.SESSIONS_FILE + ".tmp")
    tmp.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in keep), encoding="utf-8")
    tmp.replace(root / pm.SESSIONS_FILE)
    if moved_turns or moved_sessions:
        logger.info(
            "persona archive %s: %d turns, %d sessions, days=%s",
            root.parent.name, moved_turns, moved_sessions, days,
        )
    return {"turns": moved_turns, "sessions": moved_sessions, "days": days}


def retire_note(root: Path, kind: str, text: str, as_of: str) -> None:
    """A note the persona pruned from its file. Kept, dated, marked retired."""
    conn = open_db(root)
    try:
        conn.execute(
            "INSERT INTO notes (kind, text, as_of, retired_at) VALUES (?,?,?,date('now'))",
            (kind, text, as_of),
        )
        conn.commit()
    finally:
        conn.close()


def query_day(root: Path, day: str) -> list[dict]:
    live = pm.read_log(root, day)
    if live:
        return [dict(e) for e in live]
    conn = open_db(root)
    try:
        return [_row(r) for r in conn.execute("SELECT * FROM turns WHERE day = ? ORDER BY ts", (day,))]
    finally:
        conn.close()


def query_session(root: Path, session_id: str) -> list[dict]:
    conn = open_db(root)
    try:
        rows = [_row(r) for r in conn.execute(
            "SELECT * FROM turns WHERE session = ? ORDER BY ts", (session_id,)
        )]
    finally:
        conn.close()
    if rows:
        return rows
    for row in pm.read_sessions(root):
        if row.get("id") == session_id:
            return [e for e in pm.read_log(root, row.get("day", "")) if e.get("session") == session_id]
    return []


def _search_live(root: Path, words: list[str], limit: int) -> list[dict]:
    """The live week, which the database has not absorbed yet.

    query_day already reads the loose files before the tables; a search that
    read only the tables would answer "no record" for everything a persona
    did this week, which is the week it is most often asked about. Substring
    matching, because there is no index over a file and the week is small.
    """
    out: list[dict] = []
    today = date.today()
    for i in range(0, 8):
        day = (today - timedelta(days=i)).isoformat()
        for e in pm.read_log(root, day):
            hay = " ".join(
                str(x)
                for x in (
                    e.get("question"),
                    e.get("answer"),
                    " ".join(str(t) for t in (e.get("touched") or [])),
                )
                if x
            ).lower()
            if all(w in hay for w in words):
                out.append(dict(e) | {"kind": "turn"})
    for kind, filename in (("note", pm.NOTES_FILE), ("note", pm.USER_FILE)):
        for entry in pm.read_entries(Path(root) / filename):
            if all(w in entry.lower() for w in words):
                out.append({"kind": kind, "text": entry, "as_of": entry[:10]})
    return sorted(out, key=lambda r: r.get("ts") or r.get("as_of") or "", reverse=True)[:limit]


def search(root: Path, query: str, limit: int = 20) -> list[dict]:
    words = [w.lower() for w in query.split() if w]
    q = " ".join(f'"{w}"' for w in query.split() if w)
    if not q:
        return []
    live = _search_live(root, words, limit)
    conn = open_db(root)
    try:
        turns = [_row(r) | {"kind": "turn"} for r in conn.execute(
            "SELECT t.* FROM turns_fts f JOIN turns t ON t.rowid = f.rowid"
            " WHERE turns_fts MATCH ? ORDER BY t.ts DESC LIMIT ?",
            (q, limit),
        )]
        notes = [dict(r) | {"kind": "note"} for r in conn.execute(
            "SELECT n.* FROM notes_fts f JOIN notes n ON n.rowid = f.rowid"
            " WHERE notes_fts MATCH ? ORDER BY n.as_of DESC LIMIT ?",
            (q, limit),
        )]
    finally:
        conn.close()
    seen = {(r.get("ts"), r.get("text")) for r in live}
    older = [r for r in turns + notes if (r.get("ts"), r.get("text")) not in seen]
    return sorted(
        live + older, key=lambda r: r.get("ts") or r.get("as_of") or "", reverse=True
    )[:limit]
