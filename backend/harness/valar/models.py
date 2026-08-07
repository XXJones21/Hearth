"""Model identifiers, resolved to files on this machine.

A persona manifest names a model. It does not say where the model is, because
where the model is depends on which machine you are standing on, and a manifest
that answers that question is a manifest that only works on one.

    "deep_model": { "id": "gemma-4-12b-qat", "n_ctx": 65536 }

The dictionary at crates/hearth-probe/dictionary.yaml already records the
filename for every tier the probe can plan, verified against the model host
rather than copied off a model card. This joins that filename to HEARTH_MODELS.

What it deliberately does not do is point at the repository's own models
directory. Weights on a mounted Windows filesystem take minutes to load where
the native filesystem takes seconds, and that difference can exceed the model
swap timeout, so the split between the two is load-bearing.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path

from .config.settings import HearthConfigError, hearth_models, hearth_root

logger = logging.getLogger("valar.models")

# Dictionary tiers are numbered; persona manifests name them. This is the one
# place the two vocabularies meet, and scripts/render_config.py holds the same
# table for the install record.
_TIER_IDS = {
    0: "gemma-4-e2b",
    1: "gemma-4-e4b",
    2: "gemma-4-12b-qat",
    3: "gemma-4-26b-a4b",
}


class ModelNotFound(RuntimeError):
    """A persona named a model that no dictionary entry describes."""


def _dictionary_candidates() -> list[Path]:
    configured = (os.environ.get("HEARTH_DICTIONARY") or "").strip()
    if configured:
        return [Path(configured).expanduser()]
    try:
        root = hearth_root()
    except HearthConfigError:
        return []
    return [
        # The image, where the dictionary ships inside the product tree.
        root / "dictionary.yaml",
        # A checkout, where it lives with the probe that owns it.
        root.parent / "crates" / "hearth-probe" / "dictionary.yaml",
    ]


@lru_cache(maxsize=1)
def dictionary() -> dict[str, dict]:
    """id -> the tier entry, or an empty mapping when no dictionary is found."""
    import yaml

    for path in _dictionary_candidates():
        try:
            raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, ValueError):
            continue
        tiers = {}
        for tier in raw.get("tiers") or []:
            name = _TIER_IDS.get(tier.get("id"))
            if name:
                tiers[name] = tier
        if tiers:
            logger.info("model dictionary loaded from %s (%d tiers)", path, len(tiers))
            return tiers
    logger.warning(
        "no model dictionary found; personas naming a model id cannot be resolved. "
        "Looked at: %s",
        ", ".join(str(p) for p in _dictionary_candidates()) or "(nowhere, no root)",
    )
    return {}


def filename_for(model_id: str) -> str:
    """The GGUF filename the dictionary records for an id."""
    entry = dictionary().get(model_id)
    if entry is None:
        raise ModelNotFound(
            f"no model dictionary entry for {model_id!r}; "
            f"known ids: {', '.join(sorted(dictionary())) or 'none'}"
        )
    return str(entry["file"])


def resolve(spec: dict | None) -> str:
    """A persona's model block to an absolute path, or '' when it has no model.

    Accepts the shipped shape, ``{"id": ..., "n_ctx": ...}``. A manifest that
    still carries an absolute ``path`` is honoured so a developer can point a
    persona at a file by hand, but nothing shipped does.
    """
    if not spec:
        return ""
    # What the installer actually placed, which outranks the persona's declared
    # id for the same reason it does in the supervisor: the persona ships one
    # id, the plan picks a tier per machine, and the router's model-class key
    # has to name the file llama-server is really serving.
    installed = (os.environ.get("HEARTH_DEEP_MODEL_FILE") or "").strip()
    if installed:
        return installed
    legacy = str(spec.get("path") or "").strip()
    if legacy:
        return legacy
    model_id = str(spec.get("id") or "").strip()
    if not model_id:
        return ""
    try:
        return str(hearth_models() / filename_for(model_id))
    except ModelNotFound as exc:
        logger.warning("%s", exc)
        return ""
