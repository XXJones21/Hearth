"""The session record: what was said, written as it is said.

Everything else that keeps a conversation writes it at the END: the Engram
diary, the continuity note, the chatlog fallback. That made durability a
question of shutdown timing, and shutdown is exactly when there is no time.
Quitting the app killed the house while the summariser was still thinking, and
a day of conversation went with it (live 2026-08-15, three turns lost 21ms
after the write began).

So this layer writes one turn at a time, as each turn completes. No model call,
no summary, no Engram dependency. A hard kill costs the turn in flight and
nothing else, and a house with no second brain connected still keeps every
word.

    <sessions root>/YYYY-MM-DD/<session_id>/
        chatlog.md   the transcript, appended per turn
        meta.json    id, persona, platform, times, turns, title, synced

`chatlog.md` is byte-compatible with the format ``brain_sync`` writes into
Engram, so ``session_resume.parse_chatlog`` reads either without knowing which
it got. The Engram copy stays the CURATED view: journal sync promotes a record
into a diary later, when there is time to summarise it, and marks the record
synced so it is never promoted twice.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from ..config.settings import hearth_home

logger = logging.getLogger("valar.session_record")

# One line of the operator's own words, as the name of the conversation.
_TITLE_CHARS = 70


def sessions_root() -> Path:
    """Where records live. Product-owned, deliberately NOT inside the memory
    tree: disconnecting or moving a second brain must never take the
    conversation history with it."""
    return hearth_home() / "sessions"


def _day(when: float | None = None) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(when))


def _record_dir(session_id: str, when: float | None = None) -> Path:
    return sessions_root() / _day(when) / session_id


def _find_dir(session_id: str) -> Path | None:
    """A record by id, wherever its day is. Sessions opened before midnight
    and continued after it live under the day they started."""
    root = sessions_root()
    if not root.is_dir():
        return None
    for day in sorted(root.iterdir(), reverse=True):
        if not day.is_dir():
            continue
        candidate = day / session_id
        if candidate.is_dir():
            return candidate
    return None


def _read_meta(path: Path) -> dict:
    try:
        return json.loads((path / "meta.json").read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001 - a record with unreadable meta still has a chatlog
        return {}


def _write_meta(path: Path, meta: dict) -> None:
    tmp = path / "meta.json.tmp"
    tmp.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path / "meta.json")


def append_turn(session, user: str, assistant: str, persona: str = "") -> None:
    """Append one completed exchange. Never raises: a failed record must not
    break the turn the operator is having."""
    try:
        user = (user or "").strip()
        assistant = (assistant or "").strip()
        if not user and not assistant:
            return
        session_id = str(getattr(session, "session_id", "") or "unknown")
        started = getattr(session, "started_at", None)
        path = _find_dir(session_id) or _record_dir(session_id, started)
        path.mkdir(parents=True, exist_ok=True)

        meta = _read_meta(path)
        now = time.time()
        if not meta:
            meta = {
                "session_id": session_id,
                "started_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(started or now)),
                "turns": 0,
                "title": "",
                "synced": False,
            }
        meta["persona"] = persona or meta.get("persona") or ""
        meta["platform"] = getattr(session, "platform", "") or meta.get("platform") or ""
        meta["topic"] = getattr(session, "topic_hint", None) or meta.get("topic") or ""
        meta["last_turn_at"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now))
        meta["turns"] = int(meta.get("turns") or 0) + 1
        if not meta.get("title") and user:
            one_line = " ".join(user.split())
            meta["title"] = one_line[:_TITLE_CHARS]
        # A turn after a sync belongs to the same conversation, so the record
        # is dirty again and the next sync should pick it up.
        meta["synced"] = False

        chatlog = path / "chatlog.md"
        chunks: list[str] = []
        if not chatlog.exists():
            chunks.append(f"# Chat Log: {meta.get('title') or 'Untitled'}\n\n")
        else:
            chunks.append("\n---\n\n")
        if user:
            chunks.append(f"### User ()\n\n{user}\n")
            if assistant:
                chunks.append("\n---\n\n")
        if assistant:
            chunks.append(f"### Assistant ()\n\n{assistant}\n")
        with chatlog.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write("".join(chunks))

        _write_meta(path, meta)
    except Exception as exc:  # noqa: BLE001 - recording never breaks a turn
        logger.warning("session record append failed: %s", exc)


def read_record(session_id: str) -> dict | None:
    """One record: its meta plus the transcript text."""
    path = _find_dir(session_id)
    if path is None:
        return None
    meta = _read_meta(path)
    try:
        text = (path / "chatlog.md").read_text(encoding="utf-8")
    except OSError:
        text = ""
    return {**meta, "session_id": session_id, "path": str(path), "chatlog": text}


def list_records(limit: int = 200) -> list[dict]:
    """Every record, newest first, without reading a single transcript."""
    root = sessions_root()
    out: list[dict] = []
    if not root.is_dir():
        return out
    try:
        days = sorted((d for d in root.iterdir() if d.is_dir()), reverse=True)
    except OSError:
        return out
    for day in days:
        try:
            entries = sorted(day.iterdir(), reverse=True)
        except OSError:
            continue
        for entry in entries:
            if not entry.is_dir():
                continue
            meta = _read_meta(entry)
            if not meta:
                continue
            out.append(
                {
                    **meta,
                    "session_id": meta.get("session_id") or entry.name,
                    "date": day.name,
                    "has_transcript": (entry / "chatlog.md").is_file(),
                    "path": str(entry),
                }
            )
            if len(out) >= limit:
                return out
    return out


def unsynced(min_turns: int = 1) -> list[dict]:
    """Records the journal has not taken yet. The nightly routine's input."""
    return [
        r
        for r in list_records()
        if not r.get("synced") and int(r.get("turns") or 0) >= min_turns
    ]


def mark_synced(session_id: str, slug: str = "") -> None:
    """Record that the journal has this one, so it is never promoted twice."""
    path = _find_dir(session_id)
    if path is None:
        return
    meta = _read_meta(path)
    if not meta:
        return
    meta["synced"] = True
    if slug:
        meta["thought_slug"] = slug
    meta["synced_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        _write_meta(path, meta)
    except Exception as exc:  # noqa: BLE001
        logger.warning("mark_synced failed for %s: %s", session_id, exc)
