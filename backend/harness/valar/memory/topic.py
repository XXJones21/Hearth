"""Resolve an Engram topic (project or life-root) to its claude.md.

``load_engram_context`` only knows ``Projects/<name>``. Career and the other
life shelves live next to Projects, not under it. The Sessions rail starts a
topic session against either kind.
"""

from __future__ import annotations

import os
from pathlib import Path

LIFE_DIRS = ("Career", "Areas", "Resources", "Research", "Ideas", "Archive")
_MAX_CHARS = 4000


def resolve_engram_root(repo_root: Path | None = None) -> Path | None:
    """Engram root from house env, then the journal candidate list."""
    for key in ("HEARTH_ENGRAM", "VALAR_ENGRAM"):
        raw = os.environ.get(key, "").strip()
        if raw:
            p = Path(raw)
            if p.is_dir():
                return p
    if repo_root is None:
        return None
    try:
        from ..gateway.journal import _engram_root as journal_root

        return journal_root(Path(repo_root))
    except Exception:  # noqa: BLE001
        return None


def _safe_name(name: str) -> str | None:
    raw = (name or "").strip()
    if not raw or "/" in raw or "\\" in raw or ".." in raw:
        return None
    return raw


def topic_claude_md(engram_root: Path, name: str) -> Path | None:
    """Path to the topic's claude.md, or None if it is not on disk."""
    safe = _safe_name(name)
    if safe is None:
        return None
    root = Path(engram_root)
    projects = root / "Projects"
    if projects.is_dir():
        direct = projects / safe / "claude.md"
        if direct.is_file():
            return direct
        lowered = safe.lower()
        for d in projects.iterdir():
            if d.is_dir() and d.name.lower() == lowered:
                p = d / "claude.md"
                if p.is_file():
                    return p
    lowered = safe.lower()
    for life in LIFE_DIRS:
        if life.lower() == lowered:
            p = root / life / "claude.md"
            if p.is_file():
                return p
            idx = root / life / "_index.md"
            if idx.is_file():
                return idx
    return None


def load_topic_context(engram_root: Path, name: str) -> str:
    """claude.md (or _index.md) body for a topic, truncated for the prompt."""
    path = topic_claude_md(engram_root, name)
    if path is None:
        return ""
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    if len(content) > _MAX_CHARS:
        content = content[:_MAX_CHARS] + "\n\n[Truncated for prompt budget.]"
    return content
