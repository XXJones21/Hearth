"""Backfill each persona's memory from the session records and ledgers the
house already keeps. Idempotent per day: a marker file under memory/
records each day done. Design: the persona private memory spec in the
Valinor repository (docs/superpowers/specs/2026-09-02-persona-private-memory-design.md).

Runs against the live house's configuration: sessions under HEARTH_HOME,
personas under HEARTH_PERSONA_DIR, exactly as the harness resolves them.

Usage: python scripts/persona_memory_backfill.py [--days N] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend" / "harness"))

from valar.config.settings import hearth_home, load_config  # noqa: E402
from valar.memory import persona_memory as pm  # noqa: E402

SESSIONS = hearth_home() / "sessions"
PERSONAS = load_config().persona_dir


def _ledger_lines(day_dir: Path) -> list[dict]:
    ledger = day_dir / "ledger.jsonl"
    if not ledger.exists():
        return []
    out: list[dict] = []
    for line in ledger.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=0, help="only the most recent N day folders (0 = all)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    print(f"sessions: {SESSIONS}\npersonas: {PERSONAS}")

    days = sorted(p for p in SESSIONS.iterdir() if p.is_dir()) if SESSIONS.is_dir() else []
    if args.days:
        days = days[-args.days:]
    total_lines = 0
    for day_dir in days:
        day = day_dir.name
        by_session: dict[str, dict] = {}
        touched_personas: set[str] = set()
        for sess in sorted(p for p in day_dir.iterdir() if p.is_dir()):
            meta_path = sess / "meta.json"
            if not meta_path.exists():
                continue
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            persona = str(meta.get("persona") or "")
            if not persona or not (PERSONAS / persona).is_dir():
                continue
            by_session[sess.name] = meta
            root = pm.memory_root(PERSONAS, persona)
            if (root / f".backfilled-{day}").exists():
                continue
            touched_personas.add(persona)
            if not args.dry_run:
                pm.upsert_session(pm.scaffold(root), {
                    "id": sess.name,
                    "day": day,
                    "client": meta.get("platform", ""),
                    "origin": "voice",
                    "title": pm.head(meta.get("title", ""), 80),
                    "turns": int(meta.get("turns") or 0),
                    "topic": meta.get("topic", ""),
                    "updated": meta.get("last_turn_at") or meta.get("started_at") or day,
                })
        day_lines = 0
        for j in _ledger_lines(day_dir):
            if j.get("kind") != "turn.decision":
                continue
            persona = str(j.get("actor") or "")
            if not persona or not (PERSONAS / persona).is_dir():
                continue
            root = pm.memory_root(PERSONAS, persona)
            if (root / f".backfilled-{day}").exists():
                continue
            touched_personas.add(persona)
            meta = by_session.get(str(j.get("session") or ""), {})
            entry = {
                "ts": j.get("ts") or f"{day}T00:00:00",
                "day": day,
                "session": j.get("session", ""),
                "origin": "voice",
                "client": meta.get("platform", ""),
                "question": pm.head(j.get("question", "")),
                "tools": list(j.get("tools_invoked") or []),
                "touched": list(j.get("tools_invoked") or []),
                "answer": pm.head(j.get("answer_head", "")),
                "dispatches": [],
            }
            day_lines += 1
            if not args.dry_run:
                pm.append_log(root, entry)
        total_lines += day_lines
        if not args.dry_run:
            for persona in touched_personas:
                (pm.scaffold(pm.memory_root(PERSONAS, persona)) / f".backfilled-{day}").touch()
        print(f"{day}: {len(by_session)} sessions, {day_lines} ledger lines, personas {sorted(touched_personas)}")
    print("done", "(dry run)" if args.dry_run else "", f"{total_lines} lines")


if __name__ == "__main__":
    main()
