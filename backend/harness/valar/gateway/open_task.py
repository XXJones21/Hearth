"""Mechanical leftover-file carry for persona tool_loop.carry.

Session history is only spoken text. list_dir already returns structured
``data.files`` / ``data.dirs``; this module turns those traces into
``session.open_task`` so the next decision call can continue a wiki ingest
without the model having to remember unread paths.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger("valar.gateway.open_task")

INJECT_CAP = 20
# Wall clock for the whole tool phase of one utterance. Raised from 90s
# 2026-08-16: with per-batch folding a turn already ran 78s and read only a
# handful of files, so 90s bound before the batches did. A deliberate ingest
# is allowed to be slow now that every batch is durable on disk before the
# turn ends.
BATCH_WALL_S = 240.0

# Fold policy. The Hearth wiki is ~162k tokens against a 65k window, so a
# tree bigger than the context can never finish by batching alone: every
# batch accumulates into the same message list (live 2026-08-16 `939d446c`,
# a 400 exceed_context_size at file 24 of 39). Each batch is therefore
# summarized and its raw file bodies dropped, which keeps the conversation
# flat and makes tree size stop mattering.
FOLD_MAX_CHARS = 1800
# A single "read my resume" turn must keep its file body verbatim; only a
# sweep big enough to threaten the window is worth folding. Both bars must
# be cleared. Measured against the live tree: the wiki root is 9 files and
# 65k chars, `backend` is 7 files and 77k, `raw` is 15 files and 169k after
# the read_file clip.
FOLD_MIN_READS = 3
# Raised from 20k 2026-08-16: a fold costs 12-24s, and batches were paying
# it to summarize three files. Fold when accumulation actually threatens the
# window, not on every batch. A turn always force-folds its tail before
# ending, so nothing is lost by waiting.
FOLD_MIN_CHARS = 60_000
# The fold is itself a brain call, so it obeys the same window. Bodies are
# summarized in chunks of this size (~10k tokens) and the digests joined;
# live 2026-08-16 `cbf30b9f` folded 30 files in one call and took its own
# 400 at 82,186 tokens, which left the raw bodies in place and killed the
# turn's final stream.
FOLD_CHUNK_CHARS = 40_000
FOLD_TOTAL_CHARS = 6_000
# append_file caps a single call at 4,000 chars, and a multi-chunk digest is
# routinely 5,400-6,000. Live 2026-08-16: three folds covering 34 files were
# rejected with "text too long" and never reached the note, while the one
# small fold landed. The digest is therefore appended in slices under that
# cap, split at paragraph boundaries.
APPEND_SLICE_CHARS = 3_500

# How many fold digests ride forward between utterances, and their total
# budget. Session history keeps only the spoken sentence, so these ARE the
# knowledge from the files already read; the final "write the note" turn
# composes from them. Eight digests is a ~39-file tree at ~3.5k tokens.
NOTES_MAX_ENTRIES = 8
NOTES_MAX_CHARS = 14_000

# How long a carried task may survive with no work done on it. It now
# outlives a session boundary (live 2026-08-16: the idle watchdog ended the
# session between two halves of one ingest and the remainder was discarded,
# so the next turn re-read nine files it had already read). It must not
# outlive the day and ambush an unrelated conversation tomorrow.
CARRY_TTL_S = 6 * 3600

# Tools that mean the operator is still on the file task. Anything else --
# weather, a consult, plain chat -- means the turn moved on, and a carried
# remainder must not keep stapling "call read_file now" onto unrelated
# utterances. Writes count (a new_file mid-ingest is part of the job, and
# does not by itself finish a 39-file read).
_FILE_TOOLS = frozenset(
    {"list_dir", "read_file", "new_file", "write_file", "mkdir", "search_files"}
)


def _norm(path: str) -> str:
    return (path or "").replace("/", "\\").rstrip("\\").lower()


def has_remainder(task: dict | None) -> bool:
    if not task:
        return False
    return bool(task.get("remaining_files") or task.get("remaining_dirs"))


def has_file_work(traces: list[dict[str, Any]] | None) -> bool:
    """Did this utterance touch the file tools at all?

    A remainder survives an unfinished ingest, not a change of subject. The
    caller drops the task at end of turn when this is False, so an unwalked
    ``raw/`` folder cannot carry the note forward forever.
    """
    return any(str(t.get("name") or "") in _FILE_TOOLS for t in traces or [])


def apply_trace(
    task: dict | None,
    traces: list[dict[str, Any]],
    goal: str,
) -> dict | None:
    """Merge this batch's list_dir / read_file results into the open task.

    Returns None when nothing remains. Empty traces leave the prior task as-is.
    """
    if not traces:
        return task
    task = dict(task) if task else {
        "goal": goal or "",
        "root": "",
        "read": [],
        "remaining_files": [],
        "remaining_dirs": [],
    }
    if goal and not task.get("goal"):
        task["goal"] = goal
    read_by = {_norm(p): p for p in task.get("read") or [] if p}
    files_by = {_norm(p): p for p in task.get("remaining_files") or [] if p}
    dirs_by = {_norm(p): p for p in task.get("remaining_dirs") or [] if p}
    for tr in traces:
        name = str(tr.get("name") or "")
        ok = bool(tr.get("ok"))
        data = tr.get("data") or {}
        if name == "list_dir" and ok:
            listed = str(data.get("path") or "")
            if listed:
                dirs_by.pop(_norm(listed), None)
                # The first folder listed names the job on screen.
                if not task.get("root"):
                    task["root"] = listed
            for p in data.get("files") or []:
                n = _norm(str(p))
                if n and n not in read_by:
                    files_by[n] = str(p)
            for p in data.get("dirs") or []:
                n = _norm(str(p))
                if n:
                    dirs_by[n] = str(p)
        elif name == "read_file" and ok:
            p = str(data.get("path") or "")
            if p:
                n = _norm(p)
                read_by[n] = p
                files_by.pop(n, None)
    task["read"] = list(read_by.values())
    task["remaining_files"] = list(files_by.values())
    task["remaining_dirs"] = list(dirs_by.values())
    task["stamp"] = time.time()
    if not has_remainder(task):
        return None
    return task


def is_stale(task: dict | None, ttl_s: float = CARRY_TTL_S) -> bool:
    """True when a carried task has sat untouched past its time to live.

    The task survives a session boundary on purpose, so this is the only
    thing standing between an abandoned ingest and a note injected into an
    unrelated conversation hours later. A task with no stamp is treated as
    fresh: it was written by an older build, not abandoned.
    """
    if not task:
        return False
    stamp = task.get("stamp")
    if not isinstance(stamp, (int, float)):
        return False
    return (time.time() - float(stamp)) > ttl_s


def format_note(task: dict) -> str:
    files = list(task.get("remaining_files") or [])[:INJECT_CAP]
    dirs = list(task.get("remaining_dirs") or [])[:INJECT_CAP]
    read = list(task.get("read") or [])[:INJECT_CAP]
    extra_files = max(0, len(task.get("remaining_files") or []) - len(files))
    extra_dirs = max(0, len(task.get("remaining_dirs") or []) - len(dirs))
    file_line = ", ".join(files) if files else "(none)"
    if extra_files:
        file_line += f" (+{extra_files} more)"
    dir_line = ", ".join(dirs) if dirs else "(none)"
    if extra_dirs:
        dir_line += f" (+{extra_dirs} more)"
    read_line = ", ".join(read) if read else "(none)"
    return (
        "[Open task — continue now]\n"
        f"Goal: {task.get('goal') or '(in progress)'}\n"
        f"Already read: {read_line}\n"
        f"Remaining files: {file_line}\n"
        f"Remaining folders: {dir_line}\n"
        "Call read_file on the next remaining files this turn. Several in "
        "one round is fine. Call list_dir on a remaining folder to go "
        "deeper. Then new_file if the operator asked to write. Do not ask "
        "permission. Do not announce."
    )


def remainder_phrase(task: dict | None) -> str:
    """What is left, in words the speech note can state without lying.

    The remainder can be folders only (every listed file read, ``raw/`` never
    walked), so counting files alone produced "0 unread files remain".
    """
    n_files = len((task or {}).get("remaining_files") or [])
    n_dirs = len((task or {}).get("remaining_dirs") or [])
    parts = []
    if n_files:
        parts.append(f"{n_files} unread file{'s' if n_files != 1 else ''}")
    if n_dirs:
        parts.append(f"{n_dirs} unopened folder{'s' if n_dirs != 1 else ''}")
    if not parts:
        return "Work remains"
    verb = "remains" if (n_files + n_dirs) == 1 else "remain"
    return f"{' and '.join(parts)} {verb}"


def _leaf(path: str, depth: int = 1) -> str:
    parts = [p for p in _norm(path).replace("\\", "/").split("/") if p]
    if not parts:
        return path or ""
    keep = parts[-depth:]
    original = [p for p in (path or "").replace("/", "\\").split("\\") if p]
    return "\\".join(original[-len(keep):]) if original else "/".join(keep)


def progress(
    task: dict | None,
    prev: dict | None,
    traces: list[dict[str, Any]] | None,
) -> dict | None:
    """Screen snapshot for one finished tool batch, or None when there is
    nothing worth showing.

    The turn speaks one sentence; the card is where the operator sees which
    files actually moved. Called after ``apply_trace``, so ``task`` is the new
    state and ``prev`` the old one. ``task is None`` with a ``prev`` means the
    batch finished the job, and the reads from this batch are counted out of
    the traces because the merged task no longer exists to hold them.
    """
    if not has_file_work(traces):
        return None
    current = task or prev
    if not current:
        return None
    if task is not None:
        read = list(task.get("read") or [])
    else:
        read = list((prev or {}).get("read") or [])
        seen = {_norm(p) for p in read}
        for tr in traces or []:
            if str(tr.get("name") or "") == "read_file" and tr.get("ok"):
                p = str((tr.get("data") or {}).get("path") or "")
                if p and _norm(p) not in seen:
                    seen.add(_norm(p))
                    read.append(p)
    files_left = list((task or {}).get("remaining_files") or [])
    dirs_left = list((task or {}).get("remaining_dirs") or [])
    return {
        "root": _leaf(current.get("root") or "", depth=2),
        "read": len(read),
        "files_left": len(files_left),
        "dirs_left": len(dirs_left),
        "next": [_leaf(p) for p in (files_left + dirs_left)[:3]],
        "done": task is None,
    }


def add_note(notes: list[str], digest: str) -> None:
    """Keep one more fold digest, oldest dropped first, within both budgets."""
    digest = (digest or "").strip()
    if not digest:
        return
    notes.append(digest)
    while len(notes) > NOTES_MAX_ENTRIES:
        notes.pop(0)
    while len(notes) > 1 and sum(len(n) for n in notes) > NOTES_MAX_CHARS:
        notes.pop(0)


def format_notes(notes: list[str]) -> str:
    """The carried digests, as the message injected on a later utterance."""
    body = "\n\n".join(notes)
    return (
        "[Notes from the files you already read on this job]\n"
        f"{body}\n"
        "These are your own notes from earlier. Treat them as read. Do not "
        "read those files again. Write from these when asked for a summary "
        "or a document."
    )


def ledger_head(task: dict | None) -> dict | None:
    if not task:
        return None
    files = list(task.get("remaining_files") or [])
    dirs = list(task.get("remaining_dirs") or [])
    return {
        "remaining_files": len(files),
        "remaining_dirs": len(dirs),
        "paths": (files + dirs)[:5],
    }


# ---- durable carry -------------------------------------------------------
# The whole carry lived in memory, so a house restart lost it. Live
# 2026-08-16: a continue turn read and folded 40 files and appended NONE of
# them, because `task_dest` had died with the previous process and only the
# open_note tool can set it. The remainder, the digests and the destination
# are now written beside the ledger after every fold and reloaded on the
# next turn, so "continue" keeps writing to the same note across a restart.

_STATE_NAME = "open-task.json"


def _state_path(sessions_dir: "Path") -> "Path":
    return sessions_dir / _STATE_NAME


def save_state(
    sessions_dir: "Path",
    task: dict | None,
    notes: list[str],
    dest: str,
) -> None:
    """Best-effort persist. Never breaks a turn."""
    try:
        sessions_dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "stamp": time.time(),
            "task": task,
            "notes": list(notes or []),
            "dest": dest or "",
        }
        _state_path(sessions_dir).write_text(
            json.dumps(payload, ensure_ascii=False), encoding="utf-8"
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("open task state save failed: %s", exc)


def load_state(sessions_dir: "Path") -> tuple[dict | None, list[str], str]:
    """Reload the carry after a restart. Expired or unreadable state is
    treated as absent, so a stale sweep cannot ambush a fresh conversation."""
    try:
        path = _state_path(sessions_dir)
        if not path.is_file():
            return None, [], ""
        payload = json.loads(path.read_text(encoding="utf-8"))
        stamp = payload.get("stamp")
        if not isinstance(stamp, (int, float)):
            return None, [], ""
        if (time.time() - float(stamp)) > CARRY_TTL_S:
            logger.info("open task state expired on disk; ignoring")
            return None, [], ""
        task = payload.get("task")
        notes = [str(n) for n in (payload.get("notes") or []) if n]
        dest = str(payload.get("dest") or "")
        return (task if isinstance(task, dict) else None), notes, dest
    except Exception as exc:  # noqa: BLE001
        logger.warning("open task state load failed: %s", exc)
        return None, [], ""


def clear_state(sessions_dir: "Path") -> None:
    try:
        _state_path(sessions_dir).unlink(missing_ok=True)
    except Exception as exc:  # noqa: BLE001
        logger.warning("open task state clear failed: %s", exc)
