"""The House Ledger -- SCX v2, first emitter (decision records).

Append-only, day-first, persona-attributed event log for the whole house
(tasks/hearth-org-model.md). This module is the single write seam; the
gateway process is the single writer. Layout:

    <repo>/sessions/YYYY-MM-DD/ledger.jsonl

Each line is one event: {ts, actor, kind, session, ...payload}. The first
emitter is the voice loop's per-turn DECISION record -- the observable
"why" behind tool choices (reasoning text when the persona thinks;
tools-only when reflex) that Joshua asked for when debugging agentic
behavior. Writes are best-effort: the ledger never breaks a turn.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

logger = logging.getLogger("valar.ledger")


class Ledger:
    def __init__(self, repo_root: Path):
        self.sessions_dir = Path(repo_root) / "sessions"

    def append(self, actor: str, kind: str, session: str, payload: dict) -> None:
        """Append one event to today's ledger. Best-effort; failures log."""
        try:
            day = time.strftime("%Y-%m-%d")
            day_dir = self.sessions_dir / day
            day_dir.mkdir(parents=True, exist_ok=True)
            event = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "actor": actor,
                "kind": kind,
                "session": session,
                **payload,
            }
            with (day_dir / "ledger.jsonl").open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(event, ensure_ascii=False) + "\n")
        except Exception as exc:  # noqa: BLE001 -- the ledger never breaks a turn
            logger.warning("ledger append failed (%s/%s): %s", actor, kind, exc)

    def decision(
        self,
        session: str,
        persona: str,
        question: str,
        decisions: list[dict],
        tools_invoked: list[str],
        answer_head: str,
    ) -> None:
        """The per-turn decision record (the first ledger emitter)."""
        self.append(
            actor=persona,
            kind="turn.decision",
            session=session,
            payload={
                "question": question[:300],
                "decisions": decisions,
                "tools_invoked": tools_invoked,
                "answer_head": answer_head[:300],
            },
        )
