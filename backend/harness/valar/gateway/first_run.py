"""First-run detection, and what it changes.

The wiki's rule made concrete: the interview direction loads when the house
is factory-fresh, which means every non-internal persona is one that SHIPPED
(marked "shipped": true in its manifest) and the engram holds nothing yet.
The moment create_persona writes a new resident, the next turn's detection
fails and everything here expires on its own. No client flag to trust, no
way to trigger it on a lived-in house.

While first-run is active the default persona carries the direction appended
to its system prompt and a tool set narrowed to the interview: the measured
finding behind this (2026-08-07) is that seventeen tools and no direction
meant the interview tools were never chosen, even named explicitly.
"""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path

logger = logging.getLogger("valar.first_run")

# The interview, and nothing else. Selection reliability is the whole point.
INTERVIEW_GRANTS: dict = {"domains": [], "allow": ["choice_card", "create_persona"], "deny": []}

_DIRECTION_PATH = Path(__file__).resolve().parents[1] / "data" / "first_run_direction.md"

_cache: dict = {"at": 0.0, "active": False}
_CACHE_TTL_S = 3.0


def direction_text() -> str:
    try:
        return _DIRECTION_PATH.read_text(encoding="utf-8").strip()
    except OSError as exc:
        logger.warning("first-run direction missing (%s); interview runs bare", exc)
        return ""


def _engram_empty() -> bool:
    root = os.environ.get("HEARTH_ENGRAM", "").strip()
    if not root:
        return False
    base = Path(root)
    for sub in ("Projects", "Thoughts"):
        d = base / sub
        if d.is_dir() and any(d.iterdir()):
            return False
    return True


def _all_personas_shipped(persona_dir: Path) -> bool:
    if not persona_dir.is_dir():
        return False
    for child in sorted(persona_dir.iterdir()):
        manifest = child / f"{child.name.lower()}.json"
        if not (child.is_dir() and manifest.exists()):
            continue
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if data.get("internal"):
            continue
        if not data.get("shipped"):
            return False
    return True


def active(persona_dir: Path) -> bool:
    """Whether the house is factory-fresh. Cached briefly: the scan is cheap
    but runs per turn, and three seconds of staleness cannot matter when the
    only transition is create_persona, whose own turn ends first.

    HEARTH_FORCE_FIRST_RUN=1 (debug, hearth.env) overrides the detection so
    the interview can be exercised on a lived-in install without a clean
    reinstall. While it is set the WHOLE house is in interview mode; set it
    back to 0 when done. Pairs with the client's setup stage buttons."""
    if os.environ.get("HEARTH_FORCE_FIRST_RUN", "").strip() in ("1", "true", "yes"):
        return True
    now = time.monotonic()
    if now - _cache["at"] < _CACHE_TTL_S:
        return _cache["active"]
    state = _all_personas_shipped(persona_dir) and _engram_empty()
    _cache.update(at=now, active=state)
    return state
