"""Engram memory recall adapter.

WIRED-via-reuse: delegates to the existing Server.tools.brain_sync helpers
(load_operator_facts, search_operator_facts, load_engram_context) rather than
re-reading the Engram filesystem. This is the same memory the rest of Valinor
uses. Exposed here behind a clean `recall(query)` seam so it can later be
swapped for the engram-mcp recall tool (the architecture's intended path) with
no voice-loop change.

If the existing brain_sync import fails (deps/layout), recall degrades to empty
context and the voice loop still runs — memory is additive, never required.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Optional

logger = logging.getLogger("valar.memory")


class EngramMemory:
    def __init__(self, repo_root: Path, enabled: bool = True, memory_token_budget: int = 4000):
        self.repo_root = Path(repo_root)
        self.enabled = enabled
        self.memory_token_budget = memory_token_budget
        self._brain_sync = None
        self._import_failed = False

    def _ensure_imported(self) -> bool:
        if self._brain_sync is not None:
            return True
        if self._import_failed or not self.enabled:
            return False
        try:
            from memory import brain_sync  # type: ignore
        except Exception as exc:  # noqa: BLE001
            logger.warning("Engram brain_sync unavailable, memory disabled: %s", exc)
            self._import_failed = True
            return False
        self._brain_sync = brain_sync
        return True

    def recall(self, query: str, project_hint: Optional[str] = None) -> str:
        """Return a memory context block for this turn, or '' when unavailable.

        Pulls operator facts always (they are small, always-relevant) plus, when
        a query matches stored facts or a project hint is given, the relevant
        project context. Bounded by memory_token_budget (see assembler trim).
        """
        if not self._ensure_imported():
            return ""
        bs = self._brain_sync
        parts: list[str] = []
        try:
            facts = bs.load_operator_facts()  # type: ignore[union-attr]
            if facts:
                parts.append(facts)
        except Exception as exc:  # noqa: BLE001
            logger.debug("operator facts recall failed: %s", exc)
        try:
            matched = bs.search_operator_facts(query)  # type: ignore[union-attr]
            if matched:
                parts.append("Relevant facts:\n" + "\n".join(f"- {m}" for m in matched))
        except Exception as exc:  # noqa: BLE001
            logger.debug("fact search failed: %s", exc)
        if project_hint:
            try:
                ctx = bs.load_engram_context(project_hint)  # type: ignore[union-attr]
                if ctx:
                    parts.append(ctx)
            except Exception as exc:  # noqa: BLE001
                logger.debug("project context recall failed: %s", exc)
        return "\n\n".join(p for p in parts if p).strip()
