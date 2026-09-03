"""A persona's own memory on disk: the layer beside the manifest.

Spec: docs/superpowers/specs/2026-09-02-persona-private-memory-design.md,
section 1. The persona is the author of memory.md and user.md (through a
tool that lands in plan 3); the harness is the only writer of log/,
sessions.jsonl and the archive. Nothing here reads on behalf of another
persona: every function takes the root the caller already resolved for the
persona on the turn, and there is no lookup by name string.

The live week is files a person can open. Older lines move into
mind.sqlite on the consolidation clock (persona_archive.py). A missing
tree is scaffolded on first touch, never an error.
"""

from __future__ import annotations

import json
import logging
from datetime import date, datetime
from pathlib import Path
from typing import TypedDict

logger = logging.getLogger("valar.memory.persona")

NOTES_CAP = 2200
USER_CAP = 1400
LOG_DIRNAME = "log"
DAY_DIRNAME = "day"
RECON_DIRNAME = "reconstructed"
SESSIONS_FILE = "sessions.jsonl"
NOTES_FILE = "memory.md"
USER_FILE = "user.md"

_HEAD_NOTES = "# My notes\n\nDated facts I want next time. Mine alone.\n"
_HEAD_USER = (
    "# What I know about the operator\n\n"
    "Dated facts about the person I talk with. Mine alone.\n"
)


class CapExceeded(Exception):
    """A write would push a note file past its character cap."""

    def __init__(self, cap: int, current: list[str]) -> None:
        super().__init__(f"note file would exceed {cap} characters")
        self.cap = cap
        self.current = current


class LogEntry(TypedDict, total=False):
    ts: str  # ISO local time
    day: str  # YYYY-MM-DD
    session: str
    origin: str  # voice | text | routine | dispatch/<Persona> | room/<name>
    client: str  # desktop | ios | android | visionos | ... | ""
    question: str  # head, 300 chars
    tools: list[str]
    touched: list[str]  # "<tool> <target>" pairs, best effort
    answer: str  # head, 300 chars
    dispatches: list[str]


def memory_root(persona_dir: Path, name: str) -> Path:
    return Path(persona_dir) / name / "memory"


def scaffold(root: Path) -> Path:
    """Create the tree if missing. Idempotent; never touches existing content."""
    root = Path(root)
    for sub in (LOG_DIRNAME, DAY_DIRNAME, RECON_DIRNAME):
        (root / sub).mkdir(parents=True, exist_ok=True)
    notes = root / NOTES_FILE
    if not notes.exists():
        notes.write_text(_HEAD_NOTES, encoding="utf-8")
    user = root / USER_FILE
    if not user.exists():
        user.write_text(_HEAD_USER, encoding="utf-8")
    sessions = root / SESSIONS_FILE
    if not sessions.exists():
        sessions.write_text("", encoding="utf-8")
    return root


# ---------------------------------------------------------------- note files


def _split_head(text: str) -> tuple[str, str]:
    """The file is a heading block, a blank line, then entries. Keep the head."""
    if "\n\n- " in text:
        head, _, rest = text.partition("\n\n- ")
        return head + "\n", "- " + rest
    if text.startswith("- "):
        return "", text
    return text if text.endswith("\n") else text + "\n", ""


def read_entries(path: Path) -> list[str]:
    path = Path(path)
    if not path.exists():
        return []
    _, body = _split_head(path.read_text(encoding="utf-8"))
    out: list[str] = []
    for block in body.split("\n\n"):
        block = block.strip()
        if block.startswith("- "):
            out.append(block[2:].strip())
    return out


def _render(head: str, entries: list[str]) -> str:
    body = "\n\n".join(f"- {e}" for e in entries)
    return (head.rstrip("\n") + "\n\n" + body + "\n") if body else head


def write_entries(path: Path, entries: list[str], cap: int) -> None:
    path = Path(path)
    head = _split_head(path.read_text(encoding="utf-8"))[0] if path.exists() else ""
    text = _render(head, entries)
    if len(text) > cap:
        raise CapExceeded(cap, read_entries(path))
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def append_entry(path: Path, text: str, cap: int, day: str | None = None) -> str:
    """Stamp and append one entry. The stamp is the harness's, never the model's."""
    stamp = day or date.today().isoformat()
    text = " ".join(str(text).split())
    entry = text if text.startswith(stamp) else f"{stamp}: {text}"
    entries = read_entries(path) + [entry]
    write_entries(path, entries, cap)
    return entry


# ------------------------------------------------------------ activity log


def _today() -> str:
    return date.today().isoformat()


def append_log(root: Path, entry: LogEntry) -> Path:
    root = scaffold(root)
    entry = dict(entry)
    entry.setdefault("ts", datetime.now().isoformat(timespec="seconds"))
    entry.setdefault("day", entry["ts"][:10])
    path = root / LOG_DIRNAME / f"{entry['day']}.jsonl"
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return path


def read_log(root: Path, day: str) -> list[LogEntry]:
    path = Path(root) / LOG_DIRNAME / f"{day}.jsonl"
    if not path.exists():
        return []
    out: list[LogEntry] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def read_sessions(root: Path) -> list[dict]:
    path = Path(root) / SESSIONS_FILE
    if not path.exists():
        return []
    rows: dict[str, dict] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("id"):
            rows[row["id"]] = row
    return list(rows.values())


def upsert_session(root: Path, row: dict) -> None:
    """Append-only on disk, last row per id wins on read. Rewritten compact by consolidation."""
    root = scaffold(root)
    row = dict(row)
    row.setdefault("day", _today())
    row.setdefault("updated", datetime.now().isoformat(timespec="seconds"))
    with (root / SESSIONS_FILE).open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


_TARGET_KEYS = ("path", "dest", "file", "target", "agent", "persona", "name", "query", "project", "url")


def touched_from_trace(trace: list[dict] | None) -> list[str]:
    """'<tool> <target>' for each traced call, from the result data the loop keeps.

    Best effort by design: the trace carries result data, not arguments, so a
    tool whose result names nothing yields the bare tool name. Plan 2 of the
    coherence task widens what tools report; this reads whatever is there.
    """
    out: list[str] = []
    for t in trace or []:
        name = str(t.get("name") or "")
        if not name:
            continue
        data = t.get("data") or {}
        target = ""
        for key in _TARGET_KEYS:
            val = data.get(key) if isinstance(data, dict) else None
            if isinstance(val, str) and val:
                target = val
                break
        out.append(f"{name} {target}".strip())
    return out


def head(text: str, n: int = 300) -> str:
    return " ".join(str(text or "").split())[:n]
