"""Minimal persona engine — load persona.json, system prompt, voice reference.

WIRED: reads the existing Persona/<Name>/<name>.json files directly (same files
the Rust persona.rs and the Server ModelManager read). NO 6000-char persona cap
is applied — the system prompt is used in full and only bounded by the sane,
config-driven persona token budget in the context assembler.

The voice reference (reference_audio + its sibling .txt) is resolved here and
handed to the TTS adapter so NeuTTS-Air clones the correct persona voice.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from ..memory import persona_memory

logger = logging.getLogger("valar.persona")


@dataclass
class Persona:
    name: str
    system_prompt: str
    voice_reference_audio: Optional[Path]
    voice_reference_text: Optional[str]
    config: dict[str, Any]  # full persona.json (visualization, voice desc, etc.)
    # The persona's own memory tree beside its manifest (spec section 1 of
    # docs/superpowers/specs/2026-09-02-persona-private-memory-design.md in
    # Valinor). Scaffolded on load so a hand-copied or pre-design persona has
    # a working tree the first time it speaks. Never read for another persona.
    memory_dir: Path = field(default_factory=lambda: Path("."))

    def public_config(self) -> dict[str, Any]:
        """Persona config safe to send to clients (for persona_config / rendering)."""
        return {
            "name": self.name,
            "classification": self.config.get("classification"),
            "visualization": self.config.get("visualization"),
            "voice": {
                "voice_description": self.config.get("voice", {}).get("voice_description"),
            },
        }


class PersonaEngine:
    """Loads and switches personas from the Persona/ directory."""

    def __init__(self, persona_dir: Path, default_persona: str):
        self.persona_dir = Path(persona_dir)
        self.default_persona = default_persona
        self._cache: dict[str, Persona] = {}
        self._current: Optional[str] = None

    # --------------------------------------------------------------- discovery
    def list_personas(self, platform: str | None = None) -> list[str]:
        """User-facing persona names for a client `platform`. Excludes:
          - `"internal": true` personas (routing/boot shells like
            valinor-orchestrate, deferred ones like f1-*), always.
          - `"desktop_only": true` personas unless platform == "desktop"
            (e.g. Mentat's 27B is too heavy for the lightweight clients; Sulivan
            stays the universal default everywhere).
        Hidden personas are still loadable by exact name (switch_persona works);
        they just don't appear in any client's picker."""
        if not self.persona_dir.is_dir():
            return []
        is_desktop = (platform or "").strip().lower() == "desktop"
        names = []
        for child in sorted(self.persona_dir.iterdir()):
            if not (child.is_dir() and self._manifest_path(child.name).exists()):
                continue
            try:
                cfg = self.load(child.name).config
            except PersonaNotFound:
                continue
            if cfg.get("internal"):
                continue
            if cfg.get("desktop_only") and not is_desktop:
                continue
            names.append(child.name)
        return names

    def _manifest_path(self, name: str) -> Path:
        # Persona/Sulivan/sulivan.json — manifest is the lowercased dir name.
        return self.persona_dir / name / f"{name.lower()}.json"

    # ------------------------------------------------------------------- load
    def load(self, name: str) -> Persona:
        if name in self._cache:
            return self._cache[name]

        manifest = self._manifest_path(name)
        if not manifest.exists():
            raise PersonaNotFound(f"no persona manifest at {manifest}")

        data = json.loads(manifest.read_text(encoding="utf-8"))
        system_prompt = data.get("system_prompt", "").strip()
        if not system_prompt:
            logger.warning("persona %s has empty system_prompt", name)

        ref_audio, ref_text = self._resolve_voice(name, data)
        # Keyed by the folder name, not the display name: a rename of what the
        # persona calls itself keeps its memory (spec, lifecycle).
        try:
            memory_dir = persona_memory.scaffold(
                persona_memory.memory_root(self.persona_dir, name)
            )
        except OSError as exc:
            logger.warning("persona %s: memory tree not writable (%s)", name, exc)
            memory_dir = persona_memory.memory_root(self.persona_dir, name)
        persona = Persona(
            name=data.get("name", name),
            system_prompt=system_prompt,
            voice_reference_audio=ref_audio,
            voice_reference_text=ref_text,
            config=data,
            memory_dir=memory_dir,
        )
        self._cache[name] = persona
        logger.info(
            "loaded persona %s (system_prompt=%d chars, voice_ref=%s)",
            persona.name,
            len(system_prompt),
            "yes" if ref_audio else "none",
        )
        return persona

    def _resolve_voice(
        self, name: str, data: dict[str, Any]
    ) -> tuple[Optional[Path], Optional[str]]:
        voice = data.get("voice", {})
        rel = voice.get("reference_audio")
        if not rel:
            return None, None
        audio_path = self.persona_dir / name / rel
        text_path = audio_path.with_suffix(".txt")
        ref_text = None
        if text_path.exists():
            ref_text = text_path.read_text(encoding="utf-8").strip()
        if not audio_path.exists():
            logger.warning("voice reference audio missing for %s: %s", name, audio_path)
            return None, ref_text
        return audio_path, ref_text

    # --------------------------------------------------------------- lifecycle
    def current(self) -> Persona:
        if self._current is None:
            self._current = self.default_persona
        return self.load(self._current)

    def switch(self, name: str) -> Persona:
        persona = self.load(name)  # validates existence before committing
        self._current = name
        logger.info("switched persona -> %s", name)
        return persona

    def current_name(self) -> str:
        return self._current or self.default_persona


class PersonaNotFound(RuntimeError):
    pass
