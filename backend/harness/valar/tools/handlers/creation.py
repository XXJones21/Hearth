"""create_persona -- the commit at the end of the interview.

Six authored fields become a complete resident: the template supplies the
structure, the colour ramp turns one hue into the whole visualization block,
the install's environment names the model, and the voice service designs a
reference clip from instruct attributes (design once, clone always). Called
once, when the interviewer could describe this person to someone else.

The engine needs no invalidation for a NEW persona: discovery re-reads the
directory and load() only caches names it has seen. The os._exit restart in
the apply route is the EDIT path's problem, not this one's.
"""

from __future__ import annotations

import colorsys
import json
import logging
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from ...config.settings import hearth_root
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.creation")

# The attribute vocabulary OmniVoice's design mode validates. Kept in sync
# with omnivoice.utils.voice_design; unknown attributes are dropped here so a
# creative interviewer cannot crash the commit.
VOICE_ATTRIBUTES = {
    "female", "male",
    "child", "teenager", "young adult", "middle-aged", "elderly",
    "very low pitch", "low pitch", "moderate pitch", "high pitch", "very high pitch",
    "whisper",
    "american accent", "australian accent", "british accent", "canadian accent",
    "chinese accent", "indian accent", "japanese accent", "korean accent",
    "portuguese accent", "russian accent",
}

_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 '\-]{1,23}$")
_HEX_RE = re.compile(r"^#?([0-9a-fA-F]{6})$")

# The interview's five starting swatches, by the names the direction teaches.
# The live Pip run died on colour="Clay": the person answered with the name
# Sulivan offered, the model passed it through, and the strict hex gate
# killed the whole commit. A name we ourselves put in someone's mouth must
# be a colour we accept.
_SWATCHES = {
    "ember": "#E39A5B",
    "tide": "#5B9CC9",
    "fern": "#7BA85F",
    # Was "heather": a live run named the persona after the swatch the person
    # tapped for the colour question. No swatch may double as a person's name.
    "plum": "#9B72B8",
    "clay": "#C96B6B",
}
_DEFAULT_COLOUR = _SWATCHES["ember"]

# Every made persona learns the voice's non-verbal vocabulary. OmniVoice
# performs these tags instead of reading them, which gives a designed voice
# some life a system prompt alone cannot: a laugh that is a laugh. Kept to a
# short leash in the wording; a 12B told about thirteen toys will use five a
# sentence.
_VOICE_TAG_NOTE = (
    "\n\nYour voice can perform as well as speak. You may place these tags "
    "inline in a reply, where the feeling belongs, and they will be sounded "
    "rather than read: [laughter], [sigh], [confirmation-en], [question-en], "
    "[question-ah], [question-oh], [question-ei], [question-yi], "
    "[surprise-ah], [surprise-oh], [surprise-wa], [surprise-yo], "
    "[dissatisfaction-hnn]. Use at most one or two per reply, and only when "
    "the moment truly calls for it."
)


def _coerce_colour(raw: str) -> tuple[str, str]:
    """(hex, note). A hex passes through; a swatch name maps; a hex buried
    in a sentence is dug out. Anything else falls back to Ember with a note
    for the model rather than failing the commit: a persona with a default
    colour exists, a persona rejected over a colour does not."""
    text = str(raw or "").strip()
    m = _HEX_RE.match(text)
    if m:
        return f"#{m.group(1).upper()}", ""
    named = _SWATCHES.get(text.lower())
    if named:
        return named, ""
    buried = re.search(r"#([0-9a-fA-F]{6})\b", text)
    if buried:
        return f"#{buried.group(1).upper()}", ""
    logger.warning("create_persona colour %r not usable; defaulting to Ember", raw)
    return _DEFAULT_COLOUR, (
        f"The colour {text!r} was not a hex or a known swatch, so they wear "
        "Ember for now; it can be changed later."
        if text
        else "No colour was given, so they wear Ember for now."
    )


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def _hex_to_rgb(hex_str: str) -> tuple[float, float, float]:
    raw = _HEX_RE.match(hex_str.strip()).group(1)  # caller validated
    return tuple(int(raw[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def _shade(rgb: tuple[float, float, float], l_mul: float, s_mul: float = 1.0) -> dict:
    h, l, s = colorsys.rgb_to_hls(*rgb)
    r, g, b = colorsys.hls_to_rgb(h, _clamp(l * l_mul, 0.08, 0.9), _clamp(s * s_mul))
    return {"r": round(r, 3), "g": round(g, 3), "b": round(b, 3)}


def _ramp(hex_colour: str) -> dict:
    """One hue into the whole visualization vocabulary: the sphere, the
    particles, and the four state colours. The multipliers mirror the
    relationships in Sulivan's hand-tuned block: listening brightest,
    speaking deepest, thinking slightly muted."""
    base = _hex_to_rgb(hex_colour)
    sphere = _shade(base, 0.95)
    particles = _shade(base, 1.1, 1.05)
    return {
        "sphere_color": {**sphere, "a": 0.35},
        "particle_color": {**particles, "a": 0.78},
        "state_colors": {
            "idle": _shade(base, 1.0),
            "listening": _shade(base, 1.22, 1.05),
            "thinking": _shade(base, 0.92, 0.9),
            "speaking": _shade(base, 0.82),
        },
    }


def _design_binary() -> Path | None:
    """The voice-design CLI.

    Resolved from the INSTALL's environment, not from hearth_root(). That
    distinction cost a live first run on 2026-08-08: hearth_root() is the
    product tree -- the directory holding manifest.yaml, which in an install is
    <root>/runtime/backend -- so <root>/runtime/omnivoice-tts resolved to
    <root>/runtime/backend/runtime/omnivoice-tts and reported "unavailable"
    while the binary sat installed and correct one level up. The bug survived a
    unit test because the test set HEARTH_OMNIVOICE_TTS by hand.

    HEARTH_OMNIVOICE_TTS is written by config_gen.rs and is the answer. Older
    installs predate it, so fall back to the engine's own path -- the two
    binaries ship together and land in the same directory.
    """
    configured = (os.environ.get("HEARTH_OMNIVOICE_TTS") or "").strip()
    if configured:
        p = Path(configured).expanduser()
        return p if p.is_file() else None

    engine = (os.environ.get("HEARTH_TTS_ENGINE_BIN") or "").strip()
    if engine:
        name = "omnivoice-tts.exe" if os.name == "nt" else "omnivoice-tts"
        p = Path(engine).expanduser().parent / name
        return p if p.is_file() else None
    return None


def _voice_models() -> tuple[Path, Path] | None:
    """The GGUF pair the engine runs on, from the same directory tts-server
    is pointed at. Same reasoning as above: the install says where, not the
    product tree."""
    explicit_base = (os.environ.get("HEARTH_TTS_MODEL") or "").strip()
    explicit_codec = (os.environ.get("HEARTH_TTS_CODEC") or "").strip()
    if explicit_base and explicit_codec:
        b, c = Path(explicit_base).expanduser(), Path(explicit_codec).expanduser()
        return (b, c) if b.is_file() and c.is_file() else None

    configured = (os.environ.get("HEARTH_TTS_VOICE_MODELS") or "").strip()
    if not configured:
        return None
    voice_dir = Path(configured).expanduser()
    bases = sorted(voice_dir.glob("omnivoice-base-*.gguf"))
    codecs = sorted(voice_dir.glob("omnivoice-tokenizer-*.gguf"))
    if not bases or not codecs:
        return None
    return bases[0], codecs[0]


def _design_voice(text: str, attributes: list[str]) -> bytes | None:
    """Design the persona's reference clip from instruct attributes.

    Two engines, one preference order. The cpp CLI (omnivoice-tts --instruct)
    is first: on machines that ship the cpp engine the streaming server
    cannot design (its /v1/audio/speech validates `voice` against startup
    names), and the service /design does not exist there at all. Where the
    CLI is not built (Windows today), the torch voice service still runs and
    its /design endpoint works -- the path every made persona used before the
    cpp migration -- so it stays as the fallback rather than the platform
    losing designed voices entirely (live regression 2026-08-08: a persona
    with voice_ref=none spoke in Sulivan's clone).

    Returns WAV bytes, or None when neither engine can design -- a normal
    state, because a house with no voice engine still makes personas.
    """
    wav = _design_via_cli(text, attributes)
    if wav is not None:
        return wav
    return _design_via_service(text, attributes)


def _design_via_service(text: str, attributes: list[str]) -> bytes | None:
    """POST /design on the torch voice service (the pre-cpp path). None when
    the service is absent or cannot design (the cpp tts bridge has no such
    endpoint)."""
    import urllib.request

    url = os.environ.get("HEARTH_TTS_SERVICE_URL", "ws://127.0.0.1:18702/tts")
    base = url.replace("ws://", "http://").replace("wss://", "https://")
    if base.endswith("/tts"):
        base = base[: -len("/tts")]
    req = urllib.request.Request(
        f"{base}/design",
        data=json.dumps({"text": text, "attributes": attributes}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        # Voice design is a full synthesis pass; a cold engine adds a load.
        with urllib.request.urlopen(req, timeout=180) as resp:
            if resp.status == 200:
                logger.info(
                    "voice design (service) produced a clip for '%s'",
                    ", ".join(attributes),
                )
                return resp.read()
            logger.warning("voice design (service) HTTP %s", resp.status)
    except Exception as exc:  # noqa: BLE001 - unavailable is a normal state
        logger.info("voice design (service) unavailable: %s", exc)
    return None


def _design_via_cli(text: str, attributes: list[str]) -> bytes | None:
    """The cpp engine's design path (omnivoice-tts --instruct), a one-shot
    subprocess. Design once, clone always: what this returns becomes the
    reference every later sentence is cloned from, so the runtime never
    depends on design support and this can afford to be a subprocess."""
    binary = _design_binary()
    models = _voice_models()
    if not binary or not models:
        logger.info(
            "voice design unavailable: binary=%s (HEARTH_OMNIVOICE_TTS=%r) "
            "models=%s (HEARTH_TTS_VOICE_MODELS=%r)",
            bool(binary), os.environ.get("HEARTH_OMNIVOICE_TTS", ""),
            bool(models), os.environ.get("HEARTH_TTS_VOICE_MODELS", ""),
        )
        return None
    base, codec = models

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "design.wav"
        cmd = [
            str(binary),
            "--model", str(base),
            "--codec", str(codec),
            "--instruct", ", ".join(attributes),
            "-o", str(out),
        ]
        try:
            proc = subprocess.run(
                cmd,
                input=text.encode("utf-8"),   # the CLI takes target text on stdin
                capture_output=True,
                timeout=300,                  # a cold model load plus a full pass
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            logger.warning("voice design failed to run: %s", exc)
            return None
        if proc.returncode != 0 or not out.is_file():
            tail = (proc.stderr or b"").decode("utf-8", "replace").strip().splitlines()
            logger.warning(
                "voice design exited %s: %s",
                proc.returncode, tail[-1] if tail else "(no output)",
            )
            return None
        data = out.read_bytes()
    logger.info("voice design produced %d bytes for '%s'", len(data), ", ".join(attributes))
    return data


def create_persona(
    name: str = "",
    description: str = "",
    system_prompt: str = "",
    temperament: str = "",
    voice_design: Any = None,
    colour: str = "",
    **_: Any,
) -> ToolResult:
    name = str(name or "").strip()
    if not _NAME_RE.match(name):
        logger.warning("create_persona rejected: bad name %r", name)
        return ToolResult(
            content=(
                "The name needs to start with a letter and stay under 24 "
                "characters (letters, digits, spaces, hyphens)."
            ),
            ok=False,
        )
    description = str(description or "").strip()
    system_prompt = str(system_prompt or "").strip()
    temperament = str(temperament or "").strip()
    # One of the two texts missing is recoverable from the other; both
    # missing means there is no person here to make.
    if not description and system_prompt:
        description = system_prompt.split(".")[0].strip()[:160]
    if not system_prompt and description:
        system_prompt = (
            f"You are {name}. {description}"
            + (f" Your temperament is {temperament}." if temperament else "")
            + " Speak briefly and naturally, in your own voice."
        )
    if not description or not system_prompt:
        logger.warning(
            "create_persona rejected: no description or system_prompt (name=%r)", name
        )
        return ToolResult(
            content="A persona needs a description and a system prompt before it can exist.",
            ok=False,
        )
    colour, colour_note = _coerce_colour(colour)

    persona_dir = hearth_root() / "personas"
    dir_name = name.replace(" ", "")
    # NTFS is case-insensitive; an existing Wren blocks a wren.
    for child in persona_dir.iterdir() if persona_dir.is_dir() else []:
        if child.name.lower() == dir_name.lower():
            logger.warning("create_persona rejected: %r already exists", child.name)
            return ToolResult(
                content=f"A persona named {child.name} already lives here.",
                ok=False,
            )

    template_path = hearth_root() / "harness" / "valar" / "data" / "persona_template.json"
    if not template_path.exists():
        # A checkout runs harness/ as the root's child; an install the same.
        # Fall back to resolving beside this module.
        template_path = Path(__file__).resolve().parents[2] / "data" / "persona_template.json"
    manifest = json.loads(template_path.read_text(encoding="utf-8"))
    manifest.pop("_comment", None)

    manifest["name"] = name
    manifest["description"] = description[:160]
    manifest["temperament"] = temperament[:80]
    manifest["system_prompt"] = system_prompt[:4000] + _VOICE_TAG_NOTE

    ramp = _ramp(colour)
    vis = manifest["visualization"]
    vis["sphere"]["color"] = ramp["sphere_color"]
    vis["particle_system"]["color"] = ramp["particle_color"]
    vis["state_colors"] = ramp["state_colors"]

    # The machine's own model, from the install's environment. A persona made
    # here runs what this machine downloaded; the template's architecture and
    # sampling stand.
    manifest["deep_model"]["id"] = os.environ.get("HEARTH_MODEL_ID", "gemma-4-12b-qat")
    try:
        manifest["deep_model"]["n_ctx"] = int(os.environ.get("HEARTH_LLAMA_CTX", "32768"))
    except ValueError:
        manifest["deep_model"]["n_ctx"] = 32768

    # A list is the contract, but a comma-joined string still means the same
    # attributes; dropping it silently would cost the persona their voice.
    if isinstance(voice_design, str):
        raw_attrs: list = [p.strip() for p in voice_design.split(",") if p.strip()]
    elif isinstance(voice_design, list):
        raw_attrs = voice_design
    else:
        raw_attrs = []
    attrs = [a for a in (str(x).strip().lower() for x in raw_attrs) if a in VOICE_ATTRIBUTES]
    dropped = len(raw_attrs) - len(attrs)
    sample_text = f"Hello. I'm {name}. {description}"[:220]

    voice_note = ""
    wav = _design_voice(sample_text, attrs) if attrs else None
    target = persona_dir / dir_name
    voice_dir = target / "voice"
    target.mkdir(parents=True, exist_ok=False)
    voice_dir.mkdir()

    manifest["voice"]["voice_description"] = ", ".join(attrs) if attrs else "undesigned"
    manifest["voice"]["design"] = attrs
    if wav:
        clip = voice_dir / f"{dir_name.lower()}_voice_reference.wav"
        clip.write_bytes(wav)
        clip.with_suffix(".txt").write_text(sample_text, encoding="utf-8")
        manifest["voice"]["reference_audio"] = f"voice/{clip.name}"
        voice_note = "Their voice is designed and saved."
    else:
        manifest["voice"]["reference_audio"] = None
        manifest["voice"]["pending_design"] = True
        voice_note = (
            "Their voice design is recorded and will be made the first time "
            "the voice service is available."
        )

    manifest_path = target / f"{dir_name.lower()}.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    logger.info(
        "create_persona: %s (%d attrs%s, colour %s)",
        name,
        len(attrs),
        f", {dropped} dropped" if dropped else "",
        colour,
    )
    return ToolResult(
        content=(
            f"{name} exists now. {voice_note} "
            + (f"{colour_note} " if colour_note else "")
            + "Stop speaking as yourself after this turn: the house will "
            f"hand over, and {name} speaks next."
        ),
        data={"persona_created": dir_name},
    )
