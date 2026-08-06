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
from pathlib import Path

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.memory")

# Valar lives at <repo>/Valar/valar/tools/handlers/memory.py; repo root is 5 up.
_REPO_ROOT = Path(__file__).resolve().parents[4]

# Knowledge tier (2026-06-06): operator-facts alone is NOT the operator's
# memory -- the rich background (career history, project context) lives in
# Engram's context files. recall searches these as a second tier so "what
# about my time at Meta" finds the Career notes, not just /remember'd facts.
_ENGRAM_ROOT = _REPO_ROOT / "Engram"
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

_brain_sync = None
_import_failed = False


def _ensure_brain_sync():
    """Lazily import the shared Engram helpers. Returns the module or None."""
    global _brain_sync, _import_failed
    if _brain_sync is not None:
        return _brain_sync
    if _import_failed:
        return None
    repo_str = str(_REPO_ROOT)
    if repo_str not in sys.path:
        sys.path.insert(0, repo_str)
    try:
        from Server.tools import brain_sync  # type: ignore
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


def recall(args: dict) -> ToolResult:
    """args: {query: str}. Search the operator's FULL long-term memory.

    Primary path (2026-06-06): the engram-mcp seam's four-scope search --
    saved facts + session thoughts (diaries) + project notes + background
    knowledge (Career/Areas, fuzzy STT-tolerant). The same search every other
    client gets. Falls back to the legacy two-tier (brain_sync facts + the
    local knowledge grep) when the package is unavailable."""
    query = str(args.get("query") or args.get("text") or "").strip()
    # Intent scoping (2026-06-07): lexical ranking cannot tell "my time at
    # Apple" (career intent) from Apple Vision Pro project notes -- the MODEL
    # can, so the tool exposes the intent and we narrow the Engram scopes.
    intent = str(args.get("scope") or "all").strip().lower()
    scope_map = {
        "background": ["facts", "knowledge"],
        "personal_projects": ["projects"],
        "projects": ["projects"],  # legacy alias
        "sessions": ["thoughts"],
    }
    scopes = scope_map.get(intent)  # None -> the service default (all four)

    from ...memory.service import get_engram_service

    svc = get_engram_service()
    if svc.available() and query:
        results = svc.search(query, scope=scopes, limit=10)
        if not results:
            return ToolResult(
                content=f"I don't have anything stored about '{query}'.",
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
        top = results[:max_results]
        facts = [r for r in top if r.get("scope") == "facts"]
        if facts:
            parts.append(
                "Saved facts: " + "; ".join(r.get("snippet", "") for r in facts)
            )
        for r in top:
            scope = r.get("scope")
            if scope == "thoughts":
                when = f" ({r['date']})" if r.get("date") else ""
                parts.append(f"From a past session{when}: {r.get('snippet', '')}")
            elif scope in ("projects", "knowledge"):
                parts.append(
                    f"From my notes ({r.get('source', '?')}): {r.get('snippet', '')}"
                )
        return ToolResult(
            content="Here is what I remember.\n\n" + "\n\n".join(parts),
            data={"results": results},
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
