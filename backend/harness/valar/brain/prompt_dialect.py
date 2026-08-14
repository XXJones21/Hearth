"""Model-family prompt dialect.

OpenAI chat messages are the default preset and the internal IR. When a GGUF
becomes resident the router stamps the dialect onto ChatOptions so the current
turn renders correctly even though ContextAssembler.build() already ran.

Qwen and Glimmer are reserved: detected, logged, and wired as OpenAI until
their renderers land. Gemma 3 (e.g. gemma3-270m) stays on OpenAI — filename
must contain gemma-4 / gemma4; architecture: gemma alone is not enough.
"""

from __future__ import annotations

import logging
from enum import Enum
from pathlib import Path

logger = logging.getLogger("valar.brain.dialect")

_WIRED: frozenset[str] = frozenset({"openai", "gemma4"})
_warned: set[str] = set()


class PromptDialect(str, Enum):
    OPENAI = "openai"
    GEMMA4 = "gemma4"
    QWEN = "qwen"
    GLIMMER = "glimmer"


def dialect_from_model(model_path: str, architecture: str = "") -> PromptDialect:
    """Pick a dialect from the GGUF filename, with architecture as a hint."""
    name = Path(model_path or "").name.lower()
    arch = (architecture or "").strip().lower()
    if "glimmer" in name:
        return PromptDialect.GLIMMER
    if "qwen" in name or arch == "qwen":
        return PromptDialect.QWEN
    if "gemma-4" in name or "gemma4" in name:
        return PromptDialect.GEMMA4
    return PromptDialect.OPENAI


def wire_dialect(dialect: PromptDialect | None) -> PromptDialect:
    """Dialect that actually goes on the wire. Unimplemented families -> OpenAI."""
    d = dialect or PromptDialect.OPENAI
    if d.value in _WIRED:
        return d
    if d.value not in _warned:
        logger.info("prompt dialect %s not implemented; wiring as openai", d.value)
        _warned.add(d.value)
    return PromptDialect.OPENAI
