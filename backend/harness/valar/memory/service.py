"""EngramService -- the harness's single Engram access seam (engram-mcp backed).

The same shape as the brain and TTS seams: Valar components talk to THIS class,
and the backend is pluggable via env. The backend is the shared ``engram-mcp``
package (``EngramClient``) -- the exact surface every other client (Claude Code
desktop/MacBook, future Hermes adapter) uses, with its contract-side path
safety and the in-process single-writer lock. Routing Valar through it is the
cross-client unification: one memory layer, one access contract.

Transports (env):
  HEARTH_ENGRAM_TRANSPORT  "local" (default; in-process FS via the engram-mcp
                          seams -- the co-located WSL path) or "http" (a remote
                          engram-mcp service; the off-box future).
  HEARTH_ENGRAM_URL        base URL for the http transport.
  HEARTH_ENGRAM_MCP_PATH   where the engram-mcp package lives (default:
                          <repo-parent>/claude-marketplace/engram-mcp).

PORT NOTE: the engram-mcp http service DEFAULTS to 0.0.0.0:8765 -- which on
this box is the Rust supervisor's WS control plane. If that service is ever
deployed here, set ENGRAM_MCP_PORT to something free first.

Degradation contract: if the engram-mcp package is unavailable, every method
returns its empty value and ``available()`` is False -- callers keep their
legacy seams (brain_sync / direct reads) as the fallback tier, so a missing
package never breaks a voice turn.

Current tenants: the recall/remember tool handlers. Next tenants (queued):
project_status, the per-turn SCX memory block (EngramMemory), and the
session-persist path.
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger("valar.memory.service")

_DEFAULT_SCOPES = ["facts", "thoughts", "projects", "knowledge"]


class EngramService:
    """Lazy, degradable wrapper over ``engram_mcp.client.EngramClient``."""

    def __init__(self) -> None:
        self._client: Any = None
        self._failed = False

    def _ensure(self) -> Any:
        if self._client is not None:
            return self._client
        if self._failed:
            return None
        # Product, not dev tooling (2026-08-17): the installer vendors
        # engram-mcp into the backend bundle (vendor/engram-mcp) and the
        # rendered hearth.env points here at it. There is still no derived
        # default: an unset variable means an install older than the bundling,
        # or a testbed that has not rendered its config, and the legacy seams
        # carry the load. That degradation cost weeks of shallow recall on the
        # first ported house, so it logs as a warning rather than info.
        configured = (os.environ.get("HEARTH_ENGRAM_MCP_PATH") or "").strip()
        if not configured:
            logger.warning("HEARTH_ENGRAM_MCP_PATH unset; using the legacy memory seams")
            self._failed = True
            return None
        pkg = Path(configured).expanduser()
        try:
            if (pkg / "engram_mcp").is_dir() and str(pkg) not in sys.path:
                sys.path.insert(0, str(pkg))
            from engram_mcp.client import EngramClient  # type: ignore

            transport = os.environ.get("HEARTH_ENGRAM_TRANSPORT", "local")
            base_url = os.environ.get("HEARTH_ENGRAM_URL") or None
            self._client = EngramClient(transport=transport, base_url=base_url)
            logger.info("EngramService up (transport=%s, pkg=%s)", transport, pkg)
        except Exception as exc:  # noqa: BLE001 - memory never breaks a turn
            logger.warning(
                "engram-mcp unavailable (%s); callers degrade to legacy seams", exc
            )
            self._failed = True
            return None
        return self._client

    def available(self) -> bool:
        return self._ensure() is not None

    # ---- reads (sync; the client serves them without the write lock) -----

    def search(
        self,
        query: str,
        scope: list[str] | None = None,
        limit: int = 12,
    ) -> list[dict]:
        """Full-Engram search: facts + thoughts + projects + knowledge
        (Career/Areas). Returns the raw result dicts ({scope, source, snippet,
        date}), empty on any failure."""
        client = self._ensure()
        if client is None:
            return []
        try:
            r = client.search(query, scope or list(_DEFAULT_SCOPES), limit)
            return list(r.get("results") or [])
        except Exception as exc:  # noqa: BLE001
            logger.warning("engram search failed: %s", exc)
            return []

    def recall_kind(
        self,
        kind: str,
        project: str | None = None,
        target: str | None = None,
        slug: str | None = None,
        max_chars: int = 4000,
        full: bool = False,
    ) -> dict | None:
        """Read context by kind (project/global/facts/thought/file)."""
        client = self._ensure()
        if client is None:
            return None
        try:
            return client.recall(kind, project, target, slug, max_chars, full)
        except Exception as exc:  # noqa: BLE001
            logger.warning("engram recall(%s) failed: %s", kind, exc)
            return None

    def list_projects(self) -> dict | None:
        client = self._ensure()
        if client is None:
            return None
        try:
            return client.list_projects()
        except Exception as exc:  # noqa: BLE001
            logger.warning("engram list_projects failed: %s", exc)
            return None

    # ---- writes (async; serialized by the client's write lock) -----------

    async def append(
        self,
        target: str,
        content: str,
        heading: str | None = None,
        mode: str = "append",
    ) -> dict | None:
        """Append a note to an Engram target (e.g. a project claude.md). Used by
        the Mentat conductor for run summaries. Degradable like every seam here."""
        client = self._ensure()
        if client is None:
            return None
        try:
            return await client.append(target, content, heading=heading, mode=mode)
        except Exception as exc:  # noqa: BLE001
            logger.warning("engram append failed: %s", exc)
            return None

    async def promote_fact(self, text: str, source: str) -> dict | None:
        client = self._ensure()
        if client is None:
            return None
        try:
            return await client.promote_fact(text, source)
        except Exception as exc:  # noqa: BLE001
            logger.warning("engram promote_fact failed: %s", exc)
            return None


_service = EngramService()


def get_engram_service() -> EngramService:
    """The process-wide EngramService (lazy; safe to call from handlers)."""
    return _service
