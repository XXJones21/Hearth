"""Read and write the household: the persona page's server surface.

Every field here exists in persona.json today. The page presents them in the
order a person cares about (who they are, how they are, voice, presence,
what they may do, how they think) and this module translates between that
and the file.

Two translations are worth knowing about.

**Colours** are stored as float rgb 0..1 and shown as hex, because nobody
picks a colour in floats.

**Models are named, never pathed**, in the file as well as on the page.
A manifest carries a model id the dictionary describes, and the resolver joins
it to HEARTH_MODELS. This module used to do that translation alone, at the edit
boundary, over files that stored absolute paths under one Linux user's home;
now it reads and writes the id and the picker offers what the dictionary
knows.

There is also one thing here that is neither a read nor a write. **Hear it**
(`POST /personas/speak`) sends a line through the same persistent TTS service
the voice loop uses and hands back a wav, so you can judge a clone before
committing to it. It reads the clip and transcript out of the request where
they are given, which means the button previews what is on screen rather than
what was last saved.

Writing follows the pattern Apps proved: batch the edits, write, then let
the process exit so systemd restarts it (Restart=always). persona.json is
read once at process start, so a restart is what makes an edit real.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import struct
import sys
import threading
import time
from array import array
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import JSONResponse, Response

from ..config.settings import ValarConfig
from ..models import dictionary, filename_for

logger = logging.getLogger("valar.gateway.personas")

# Personas that are machinery rather than residents. They still appear when
# developer mode asks for them; they are just not the household.
_HIDDEN_PREFIXES = ("wright-",)
_FORMS = ["non_corporeal", "humanoid", "quadruped", "custom"]


def _hex(color: dict | None) -> str | None:
    """{r,g,b} floats -> #RRGGBB."""
    if not isinstance(color, dict):
        return None
    try:
        return "#" + "".join(
            f"{max(0, min(255, round(float(color.get(c, 0)) * 255))):02X}" for c in "rgb"
        )
    except (TypeError, ValueError):
        return None


def _rgb(value: str) -> dict | None:
    """#RRGGBB -> {r,g,b} floats."""
    v = str(value or "").strip().lstrip("#")
    if len(v) != 6:
        return None
    try:
        return {c: int(v[i : i + 2], 16) / 255.0 for c, i in zip("rgb", (0, 2, 4))}
    except ValueError:
        return None


def _model_name(path: str) -> str:
    """The name a person would use for a model file."""
    stem = Path(str(path or "")).name
    for suffix in (".gguf", ".GGUF"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    return stem


def _deep_file(deep: dict) -> str:
    """The filename to show for a model block, whether it names an id or,
    for a hand-edited manifest, still carries a path."""
    model_id = str(deep.get("id") or "").strip()
    if model_id:
        try:
            return filename_for(model_id)
        except Exception:  # noqa: BLE001 - an unknown id shows as unknown
            return model_id
    return str(deep.get("path") or "")


def _model_registry(config: ValarConfig) -> dict[str, str]:
    """name -> model id. The dictionary is the registry: it is what the probe
    plans against and what a persona is allowed to name. Anything already
    downloaded is in it, and anything that is not cannot be planned for."""
    return {_model_name(entry["file"]): model_id
            for model_id, entry in dictionary().items()}


def _persona_files(config: ValarConfig) -> list[Path]:
    """<Persona>/<name>/<name>.json, the shape the engine already expects."""
    out = []
    for d in sorted(p for p in config.persona_dir.iterdir() if p.is_dir()):
        cfg = d / f"{d.name.lower()}.json"
        if cfg.exists():
            out.append(cfg)
    return out


def _voice_text_path(config: ValarConfig, key: str, rel: str) -> Path | None:
    """The .txt sidecar beside the reference wav. PersonaEngine reads this to
    align the clone, so a wrong transcript degrades the voice."""
    if not rel:
        return None
    return (config.persona_dir / key / rel).with_suffix(".txt")


def _voice_clips(config: ValarConfig, key: str) -> list[str]:
    """Every wav already sitting in the persona's folder, relative to it.

    This is what Replace picks from. Recording is out of scope, so the flow is
    the honest one: put the file in the folder (the button opens it), then
    choose it here."""
    folder = config.persona_dir / key
    try:
        found = sorted(p for p in folder.rglob("*") if p.suffix.lower() == ".wav")
    except OSError:
        return []
    return [p.relative_to(folder).as_posix() for p in found]


def _read_one(config: ValarConfig, cfg: Path) -> dict:
    doc = json.loads(cfg.read_text(encoding="utf-8"))
    key = cfg.parent.name
    vis = doc.get("visualization") or {}
    voice = doc.get("voice") or {}
    grants = doc.get("tool_grants") or {}
    loop = doc.get("tool_loop") or {}
    deep = doc.get("deep_model") or {}

    form = vis.get("form")
    if not form:
        form = "humanoid" if vis.get("type") == "glb_animated" else "non_corporeal"

    states = vis.get("state_colors") or None
    if states:
        states = {k: _hex(v) for k, v in states.items() if _hex(v)}

    ref_rel = voice.get("reference_audio", "")
    ref_text = ""
    txt = _voice_text_path(config, key, ref_rel)
    if txt and txt.exists():
        try:
            ref_text = txt.read_text(encoding="utf-8").strip()
        except OSError:
            pass

    return {
        "key": key,
        "name": doc.get("name", key),
        "description": doc.get("description", ""),
        "classification": doc.get("classification", ""),
        "internal": bool(doc.get("internal")) or key.startswith(_HIDDEN_PREFIXES),
        "system_prompt": doc.get("system_prompt", ""),
        "voice": {
            "reference_audio": ref_rel,
            "reference_text": ref_text,
            "test_line": voice.get("test_line", ""),
            "voice_description": voice.get("voice_description", ""),
            "clips": _voice_clips(config, key),
            # Replace opens this. Personas who have never had a voice have no
            # voice/ folder yet, so send the one that does exist.
            "folder": str(
                (config.persona_dir / key / "voice")
                if (config.persona_dir / key / "voice").is_dir()
                else (config.persona_dir / key)
            ),
        },
        "form": form,
        "type": vis.get("type", ""),
        "preset": vis.get("layout_preset", ""),
        "accent": _hex((vis.get("sphere") or {}).get("color"))
        or _hex((vis.get("particle_system") or {}).get("color"))
        or "#E39A5B",
        "state_colors": states,
        "domains": list(grants.get("domains") or []),
        "deny": list(grants.get("deny") or []),
        "reasoning": bool(loop.get("reasoning")),
        "rounds": int(loop.get("max_rounds") or 2),
        "model": _model_name(_deep_file(deep)),
        "temperature": float(deep.get("temperature") or 0.7),
        "n_ctx": int(deep.get("n_ctx") or 0),
    }


def _all_domains(config: ValarConfig) -> list[str]:
    try:
        import yaml  # type: ignore

        doc = yaml.safe_load(
            (Path(__file__).resolve().parents[1] / "tools" / "tools.yaml").read_text(
                encoding="utf-8"
            )
        ) or {}
    except Exception:  # noqa: BLE001
        return []
    return sorted({str(e.get("domain") or "") for e in doc.get("tools", []) or []} - {""})


def _build(config: ValarConfig) -> dict:
    people = []
    for cfg in _persona_files(config):
        try:
            people.append(_read_one(config, cfg))
        except Exception as exc:  # noqa: BLE001 - one bad file must not blank the page
            logger.warning("persona %s unreadable: %s", cfg, exc)
    return {
        "personas": people,
        "models": sorted(_model_registry(config)),
        "domains": _all_domains(config),
        "forms": _FORMS,
    }


# --------------------------------------------------------------------------- write


def _apply_one(config: ValarConfig, key: str, edit: dict, registry: dict[str, str]) -> list[str]:
    """Mutate ONLY the keys the page owns. Everything else in the file is left
    exactly as it was, which is what makes it safe to edit a persona carrying
    fields this page never shows (agent_config, chat_templates, and so on)."""
    cfg = config.persona_dir / key / f"{key.lower()}.json"
    doc = json.loads(cfg.read_text(encoding="utf-8"))
    touched: list[str] = []

    for field in ("name", "description", "system_prompt"):
        if field in edit and edit[field] != doc.get(field):
            doc[field] = edit[field]
            touched.append(field)

    voice_edit = edit.get("voice") or {}
    if voice_edit:
        voice = doc.setdefault("voice", {})
        for field in ("voice_description", "test_line"):
            if field in voice_edit and voice_edit[field] != voice.get(field):
                voice[field] = voice_edit[field]
                touched.append(f"voice.{field}")
        # Replace: only ever one of the clips already in the folder, so a
        # typo cannot point the cloner at nothing. Applied BEFORE the
        # transcript so the sidecar written below belongs to the new clip.
        new_clip = voice_edit.get("reference_audio")
        if new_clip and new_clip != voice.get("reference_audio"):
            if new_clip in _voice_clips(config, key):
                voice["reference_audio"] = new_clip
                touched.append("voice.reference_audio")
            else:
                logger.warning("%s: no such clip %r", key, new_clip)
        # the transcript is a sidecar file, not a json field
        if "reference_text" in voice_edit:
            txt = _voice_text_path(config, key, voice.get("reference_audio", ""))
            if txt:
                try:
                    current = txt.read_text(encoding="utf-8").strip() if txt.exists() else ""
                    if voice_edit["reference_text"].strip() != current:
                        txt.parent.mkdir(parents=True, exist_ok=True)
                        txt.write_text(voice_edit["reference_text"].strip() + "\n", encoding="utf-8")
                        touched.append("voice.reference_text")
                except OSError as exc:
                    logger.warning("could not write %s: %s", txt, exc)

    if "form" in edit and edit["form"] in _FORMS:
        vis = doc.setdefault("visualization", {})
        if vis.get("form") != edit["form"]:
            vis["form"] = edit["form"]
            touched.append("form")

    if isinstance(edit.get("state_colors"), dict):
        vis = doc.setdefault("visualization", {})
        colors = {}
        for state, value in edit["state_colors"].items():
            rgb = _rgb(value)
            if rgb:
                colors[state] = rgb
        if colors and colors != vis.get("state_colors"):
            vis["state_colors"] = colors
            touched.append("state_colors")

    if isinstance(edit.get("domains"), list):
        grants = doc.setdefault("tool_grants", {})
        wanted = sorted(set(edit["domains"]))
        if sorted(set(grants.get("domains") or [])) != wanted:
            grants["domains"] = wanted
            grants.setdefault("allow", [])
            grants.setdefault("deny", [])
            touched.append("domains")

    if "reasoning" in edit or "rounds" in edit:
        loop = doc.setdefault("tool_loop", {})
        if "reasoning" in edit and bool(edit["reasoning"]) != bool(loop.get("reasoning")):
            loop["reasoning"] = bool(edit["reasoning"])
            touched.append("reasoning")
        if "rounds" in edit and int(edit["rounds"]) != int(loop.get("max_rounds") or 0):
            loop["max_rounds"] = int(edit["rounds"])
            touched.append("rounds")

    deep = doc.setdefault("deep_model", {})
    if edit.get("model"):
        model_id = registry.get(edit["model"])
        if model_id and model_id != deep.get("id"):
            deep["id"] = model_id
            deep.pop("path", None)
            deep.pop("fallback_path", None)
            touched.append("model")
    if "temperature" in edit:
        temp = round(float(edit["temperature"]), 2)
        if temp != deep.get("temperature"):
            deep["temperature"] = temp
            touched.append("temperature")

    if touched:
        cfg.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return touched


def apply_changes(config: ValarConfig, payload: dict) -> dict:
    registry = _model_registry(config)
    changed: list[str] = []

    for key, edit in (payload.get("edits") or {}).items():
        cfg = config.persona_dir / key / f"{key.lower()}.json"
        if not cfg.exists():
            continue
        try:
            touched = _apply_one(config, key, edit or {}, registry)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": f"{key} could not be written: {exc}"}
        if touched:
            changed.append(f"{key}: {', '.join(touched)}")

    for key in payload.get("remove") or []:
        folder = config.persona_dir / key
        cfg = folder / f"{key.lower()}.json"
        if not cfg.exists():
            continue
        if key.lower() == (config.default_persona or "").lower():
            return {"ok": False, "error": f"{key} is the default persona; set another first."}
        # Rename rather than delete. A persona is hours of writing, and the
        # journal entries that mention them stay either way.
        retired = folder.with_name(f"{key}.removed-{int(time.time())}")
        # NTFS refuses to rename a directory while anything inside is open
        # (a voice reference, an editor). Brief retries cover the common
        # case; a real lock still reports honestly.
        rename_error: OSError | None = None
        for _ in range(3):
            try:
                folder.rename(retired)
                rename_error = None
                break
            except OSError as exc:
                rename_error = exc
                time.sleep(0.5)
        if rename_error is not None:
            return {"ok": False, "error": f"{key} could not be removed: {rename_error}"}
        changed.append(f"{key} removed (kept at {retired.name})")

    if not changed:
        return {"ok": True, "changed": [], "restarting": False}

    logger.info("personas: applied %s; restarting", "; ".join(changed))

    def _bounce() -> None:
        time.sleep(0.6)
        os._exit(0)

    threading.Thread(target=_bounce, daemon=True).start()
    return {"ok": True, "changed": changed, "restarting": True}


# --------------------------------------------------------------------------- hear it


def _wav(pcm_f32: bytes, rate: int) -> bytes:
    """float32 frames -> a 16-bit PCM wav.

    The TTS service speaks float32, which is right for the streaming path but
    not something an <audio> element reliably decodes. This is a one-shot
    preview, so convert once here rather than teach the client a second
    playback path."""
    src = array("f")
    src.frombytes(pcm_f32[: len(pcm_f32) - len(pcm_f32) % 4])
    out = array("h", (int(max(-1.0, min(1.0, s)) * 32767) for s in src))
    if sys.byteorder == "big":
        out.byteswap()
    data = out.tobytes()
    header = b"".join(
        [
            b"RIFF",
            struct.pack("<I", 36 + len(data)),
            b"WAVEfmt ",
            struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16),
            b"data",
            struct.pack("<I", len(data)),
        ]
    )
    return header + data


class _TtsFailed(RuntimeError):
    """The service answered and said no. Distinct from not answering at all,
    because the two need different words in front of a person."""


async def _synthesize(config: ValarConfig, ref_audio: Path | None, ref_text: str, text: str) -> bytes:
    """One sentence through the persistent TTS service, collected rather than
    streamed. Same protocol the voice loop uses (valar/voice/tts_remote.py)."""
    import websockets

    frames = bytearray()
    async with websockets.connect(
        config.voice.tts_service_url, ping_interval=None, max_size=None, open_timeout=10
    ) as ws:
        await ws.send(
            json.dumps(
                {
                    "text": text,
                    "ref_audio": str(ref_audio) if ref_audio else None,
                    "ref_text": ref_text or None,
                }
            )
        )
        while True:
            msg = await ws.recv()
            if isinstance(msg, (bytes, bytearray)):
                frames += msg
                continue
            obj = json.loads(msg)
            if obj.get("action") == "tts_error":
                raise _TtsFailed(obj.get("message") or "the voice service could not speak that")
            if obj.get("action") == "tts_done":
                break
    return bytes(frames)


def register(app: FastAPI, config: ValarConfig) -> None:
    @app.get("/personas/surface")
    async def personas_surface() -> JSONResponse:
        return JSONResponse(_build(config))

    @app.post("/personas/apply")
    async def personas_apply(payload: dict) -> JSONResponse:
        return JSONResponse(apply_changes(config, payload))

    @app.post("/personas/speak")
    async def personas_speak(payload: dict):
        """Hear it: speak one line in a persona's voice and hand back a wav.

        Takes the clip and transcript from the REQUEST where they are given, so
        the button previews what is on screen rather than what was last saved.
        The persona is looked up by folder, never by path, so nothing here can
        read outside Persona/."""
        key = str(payload.get("persona") or "").strip()
        cfg = config.persona_dir / key / f"{key.lower()}.json"
        if not key or "/" in key or "\\" in key or not cfg.exists():
            return JSONResponse({"ok": False, "error": "no such persona"}, status_code=404)

        doc = json.loads(cfg.read_text(encoding="utf-8"))
        voice = doc.get("voice") or {}
        clips = _voice_clips(config, key)
        rel = str(payload.get("reference_audio") or "")
        if rel not in clips:
            rel = voice.get("reference_audio", "")
        ref_audio = (config.persona_dir / key / rel) if rel else None
        if ref_audio and not ref_audio.exists():
            return JSONResponse(
                {"ok": False, "error": f"{rel} is not in {key}'s folder"}, status_code=404
            )

        ref_text = payload.get("reference_text")
        if ref_text is None:
            txt = _voice_text_path(config, key, rel)
            ref_text = txt.read_text(encoding="utf-8").strip() if txt and txt.exists() else ""

        text = str(payload.get("text") or "").strip() or voice.get("test_line", "").strip()
        if not text:
            return JSONResponse({"ok": False, "error": "nothing to say"}, status_code=400)

        try:
            pcm = await asyncio.wait_for(
                _synthesize(config, ref_audio, str(ref_text), text[:400]), timeout=90
            )
        except asyncio.TimeoutError:
            return JSONResponse(
                {
                    "ok": False,
                    "error": "The voice service did not answer in time. A clip it has "
                    "never heard before has to be encoded first, which is the slow part.",
                },
                status_code=504,
            )
        except _TtsFailed as exc:
            logger.warning("speak failed for %s: %s", key, exc)
            # The one failure worth translating. Encoding a new clone needs
            # VRAM the brain is usually already holding on the single 4080, so
            # a first press on an unheard clip is where this lands.
            oom = "out of memory" in str(exc).lower()
            return JSONResponse(
                {
                    "ok": False,
                    "error": (
                        f"Not enough VRAM to take on {rel or 'that clip'} right now. The "
                        "brain is holding it. Clips already in use still speak."
                        if oom
                        else f"The voice service could not speak that ({exc})."
                    ),
                },
                status_code=503,
            )
        except Exception as exc:  # noqa: BLE001 - the page shows whatever went wrong
            logger.warning("speak unreachable for %s: %s", key, exc)
            return JSONResponse(
                {"ok": False, "error": f"The voice service is not reachable ({exc})."},
                status_code=503,
            )
        if not pcm:
            return JSONResponse(
                {"ok": False, "error": "the voice service returned no audio"}, status_code=503
            )
        return Response(content=_wav(pcm, config.voice.output_sample_rate), media_type="audio/wav")
