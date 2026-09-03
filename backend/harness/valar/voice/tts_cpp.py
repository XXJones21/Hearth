"""OmniVoice through omnivoice.cpp, over HTTP.

The same model as tts_omnivoice.py and a different engine underneath it. The
torch build selects ``cuda:0 if torch.cuda.is_available() else cpu``, which on
Apple Silicon means the CPU and about 7.6x realtime -- unusable, and unusable
on every Mac rather than only the small ones. omnivoice.cpp is a C++/GGML
implementation with a Metal backend that clears realtime on an 8 GB Air, and
the same engine covers CUDA and Vulkan, so this is not a Mac-only detour.

The engine is a separate process (tts-server, shipped in the bundle and
supervised beside llama-server) speaking OpenAI's /v1/audio/speech. This class
is only the client: it holds no weights, so the Python side of the voice costs
a socket instead of a 2.27 GiB torch process and an isolated venv.

Streamer contract, matching OmniVoiceStreamer so everything above the TTS seam
stays engine-agnostic:

  * ``_loaded``     the engine answered /health at least once
  * ``_ref_codes``  a named voice is resolved and ready ("ready" in /health)
  * ``sync_persona_voice`` resolves the persona to a voice the engine loaded
  * ``stream_sentence``    yields float32 PCM at ``sample_rate``

Reference voices are loaded by the engine at ITS startup (--voice
name:clip.wav:transcript.txt), not per request: encoding is the expensive half
of cloning and doing it once is the whole reason the server exists. So this
class never uploads audio. It resolves a persona to a name and checks the
engine actually has it, because a persona silently speaking in the default
voice is worse than an error -- nothing downstream can tell it happened.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import AsyncIterator, Optional

import numpy as np

logger = logging.getLogger("valar.voice.tts_cpp")

# What the engine emits, fixed by the codec (24 kHz mono s16le). Resampling
# would be a lie dressed as a courtesy: the client is told the rate in
# tts_chunk_start and plays whatever it is told, so the honest move is to
# configure the rate to match rather than convert in the middle.
NATIVE_SAMPLE_RATE = 24000


class OmniVoiceCppStreamer:
    def __init__(self, repo_root: Path, service: str = "omnivoice-cpp", sample_rate: int = NATIVE_SAMPLE_RATE):
        self.repo_root = repo_root
        self.service = service
        self.sample_rate = sample_rate
        self.base_url = (os.environ.get("HEARTH_TTS_ENGINE_URL") or "http://127.0.0.1:18703").rstrip("/")
        self._voice: Optional[str] = None
        self._seen_healthy = False
        # Per-sentence voice oscillation (the persona manifest's
        # voice.oscillate list): the cycle of engine voice names to alternate
        # through, and where in it the current turn is. Empty = no
        # oscillation, the persona speaks in its primary voice.
        self._cycle: list[str] = []
        self._cycle_i = 0
        # The duet (voice.duet): every sentence rendered in BOTH voices and
        # mixed here, the under-voice swelling on a slow LFO whose phase
        # (_duet_t, seconds of mixed audio emitted) breathes continuously
        # across sentences. None = no duet.
        self._duet: Optional[dict] = None
        self._duet_t = 0.0
        if sample_rate != NATIVE_SAMPLE_RATE:
            # Not fatal: the audio is still correct, it is only labelled with a
            # rate the engine does not produce, which plays back at the wrong
            # speed. Loud, because it is silent otherwise.
            logger.warning(
                "HEARTH_TTS_SAMPLE_RATE=%d but omnivoice.cpp emits %d; audio will play at the "
                "wrong speed. Set the configured rate to %d.",
                sample_rate,
                NATIVE_SAMPLE_RATE,
                NATIVE_SAMPLE_RATE,
            )

    # --- the two flags /health reports -------------------------------------

    @property
    def _loaded(self) -> bool:  # "imported"
        return self._seen_healthy

    @property
    def _ref_codes(self):  # "ready"
        return self._voice

    # --- voice resolution ---------------------------------------------------

    @staticmethod
    def voice_name_for(ref_audio: Optional[Path]) -> Optional[str]:
        """The engine's name for a persona's reference clip.

        personas/Sulivan/voice/sulivan_voice_reference.wav -> "sulivan". The
        persona directory names the voice, so house.rs and this agree without
        a table to keep in step.
        """
        if not ref_audio:
            return None
        p = Path(ref_audio)
        try:
            return p.parent.parent.name.lower()
        except Exception:  # noqa: BLE001 - a malformed path is just "no voice"
            return None

    def _get_json(self, path: str, timeout: float = 5.0):
        with urllib.request.urlopen(f"{self.base_url}{path}", timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))

    @staticmethod
    def _voice_manifest(ref_audio: Optional[Path]) -> dict:
        """The persona manifest's voice block, found beside the clip. Missing
        or unreadable means {}: styling knobs, not health conditions."""
        if not ref_audio:
            return {}
        try:
            persona_dir = Path(ref_audio).parent.parent
            manifest = persona_dir / f"{persona_dir.name.lower()}.json"
            doc = json.loads(manifest.read_text(encoding="utf-8"))
            voice = doc.get("voice")
            return voice if isinstance(voice, dict) else {}
        except (OSError, ValueError):
            return {}

    @staticmethod
    def _oscillate_stems(ref_audio: Optional[Path]) -> list[str]:
        """The persona manifest's voice.oscillate list, read beside the clip.

        The streamer seam only carries the reference path, so the manifest is
        found from it: personas/<Name>/voice/clip.wav -> <Name>/<name>.json.
        Missing manifest or field means no oscillation, silently: this is a
        persona styling knob, not a health condition."""
        if not ref_audio:
            return []
        try:
            persona_dir = Path(ref_audio).parent.parent
            manifest = persona_dir / f"{persona_dir.name.lower()}.json"
            doc = json.loads(manifest.read_text(encoding="utf-8"))
            stems = (doc.get("voice") or {}).get("oscillate") or []
            return [str(s).strip().lower() for s in stems if str(s).strip()]
        except (OSError, ValueError):
            return []

    def sync_persona_voice(self, ref_audio: Optional[Path], ref_text: Optional[str]) -> None:
        """Resolve the persona to a voice the engine already holds.

        ref_text is unused: the engine was given the transcript alongside the
        clip at startup. It stays in the signature because the seam above is
        shared with the torch engine, which does need it.

        Oscillation: when the manifest lists voice.oscillate stems, each maps
        to the engine name "<persona>-<stem>" (house.rs registers every
        wav+txt pair in the voice folder under that name). Sentences then
        alternate through the cycle, restarting at the top of every turn so
        a reply always opens in the first voice. Stems the engine does not
        hold are dropped LOUDLY but do not fail the turn: the primary voice
        is the floor."""
        name = self.voice_name_for(ref_audio)
        body = self._get_json("/v1/voices")
        self._seen_healthy = True
        available = [v.get("name") for v in (body.get("voices") or []) if isinstance(v, dict)]
        if not name or name not in available:
            raise RuntimeError(
                f"the voice engine has no voice named {name!r} (it offers {available or 'none'}). "
                "tts-server is started with --voice <name>:<clip.wav>:<transcript.txt> per persona."
            )
        cycle: list[str] = []
        for stem in self._oscillate_stems(ref_audio):
            candidate = f"{name}-{stem}"
            if candidate in available:
                cycle.append(candidate)
            else:
                logger.warning(
                    "oscillate stem '%s' has no engine voice '%s' (clip or transcript "
                    "missing at engine start?); dropping it from the cycle",
                    stem, candidate,
                )
        new_cycle = cycle if len(cycle) >= 2 else []

        # The duet: both named voices must exist on the engine; anything less
        # degrades to the primary voice alone, loudly.
        duet_cfg = self._voice_manifest(ref_audio).get("duet")
        new_duet: Optional[dict] = None
        if isinstance(duet_cfg, dict):
            lead = f"{name}-{str(duet_cfg.get('lead') or '').strip().lower()}"
            under = f"{name}-{str(duet_cfg.get('under') or '').strip().lower()}"
            if lead in available and under in available:
                new_duet = {
                    "lead": lead,
                    "under": under,
                    "period_s": max(1.0, float(duet_cfg.get("period_s") or 10.0)),
                    "depth": max(0.05, min(1.0, float(duet_cfg.get("depth") or 0.35))),
                }
            else:
                logger.warning(
                    "duet voices %r/%r not all on the engine (offers %s); "
                    "speaking with the primary voice",
                    lead, under, available,
                )

        # The TTS service syncs PER REQUEST, one request per sentence, so
        # resetting positions here plays the first voice forever (found on
        # the first live oscillation test, 2026-09-01: twelve syncs in one
        # turn, every sentence in voice A). Position and LFO phase reset only
        # when the persona or its config actually changes.
        if name != self._voice or new_cycle != self._cycle or new_duet != self._duet:
            self._voice = name
            self._cycle = [] if new_duet else new_cycle
            self._cycle_i = 0
            self._duet = new_duet
            self._duet_t = 0.0
            logger.info(
                "voice '%s' resolved on the engine%s%s",
                name,
                f", duet {new_duet}" if new_duet else "",
                f", oscillating {self._cycle}" if self._cycle else "",
            )

    # --- synthesis ----------------------------------------------------------

    # Performance tags ([laughter], arpabet brackets) pass through WHOLE. A
    # strip lived here briefly on the theory that the tags are not registered
    # specials, so BPE tokenizes them as text and the persona reads them --
    # and a macOS first run seemed to confirm it. A controlled listening test
    # (2026-08-08, Windows CUDA, Q8_0 weights: baseline vs tagged vs
    # tag-alone WAVs, judged by ear) showed the opposite: the model performs
    # them from the plain BPE sequence, no special tokens needed -- [laughter]
    # laughs, [B EY1 S] steers pronunciation. The macOS report likely heard a
    # different failure (its design path was broken at the time). If a tag is
    # ever read aloud again, test THAT tag in isolation before re-adding any
    # strip: the display side already hides tags from the eyes (voice_loop
    # sanitize_display_text), and the ears are the only judge that counts.

    def _synth_pcm(self, voice: str, text: str) -> bytes:
        """One whole sentence as s16le PCM, blocking. The duet path needs the
        complete rendition before it can mix, so this trades the chunk stream
        for simplicity; sentences render in well under a second."""
        payload = json.dumps(
            {"model": "omnivoice", "input": text, "voice": voice, "response_format": "pcm"}
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}/v1/audio/speech",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.read()

    @staticmethod
    def _stretch_pcm(pcm: bytes, factor: float) -> bytes:
        """Time-stretch s16le mono PCM by `factor` (>1 = shorten) via ffmpeg
        atempo, pitch preserved. Any failure returns the original: the
        under-voice at its natural pace beats a broken sentence."""
        import subprocess
        import tempfile
        import wave

        factor = max(0.5, min(2.0, factor))
        try:
            with tempfile.TemporaryDirectory(prefix="duet-") as td:
                src = Path(td) / "in.wav"
                dst = Path(td) / "out.wav"
                with wave.open(str(src), "wb") as fh:
                    fh.setnchannels(1)
                    fh.setsampwidth(2)
                    fh.setframerate(NATIVE_SAMPLE_RATE)
                    fh.writeframes(pcm)
                res = subprocess.run(
                    ["ffmpeg", "-y", "-i", str(src), "-filter:a", f"atempo={factor:.4f}",
                     "-ar", str(NATIVE_SAMPLE_RATE), "-ac", "1", str(dst)],
                    capture_output=True, timeout=60,
                )
                if res.returncode != 0:
                    return pcm
                with wave.open(str(dst), "rb") as fh:
                    return fh.readframes(fh.getnframes())
        except Exception:  # noqa: BLE001 - alignment is a nicety, audio is not
            return pcm

    async def _stream_duet(self, spoken: str) -> AsyncIterator[bytes]:
        """The duet: the sentence rendered in both voices, the under-voice
        stretch-aligned onto the lead's clock, mixed with an undertone LFO
        whose phase carries across sentences (equal-power cos/sin gains).
        Degrades to the primary voice alone on any synthesis failure."""
        loop = asyncio.get_running_loop()
        d = dict(self._duet or {})
        pa = pb = b""
        try:
            pa = await loop.run_in_executor(None, self._synth_pcm, d["lead"], spoken)
            pb = await loop.run_in_executor(None, self._synth_pcm, d["under"], spoken)
        except Exception as exc:  # noqa: BLE001 - one voice failing must not wedge the turn
            logger.warning("duet synthesis failed (%s); speaking with the primary voice", exc)
        if len(pa) < 4800 or len(pb) < 4800:
            body = await loop.run_in_executor(
                None, self._synth_pcm, self._voice or d.get("lead", ""), spoken
            )
            xa = np.frombuffer(body[: len(body) // 2 * 2], dtype="<i2").astype(np.float32)
            mixed = xa / 32768.0
        else:
            if abs(len(pb) - len(pa)) > 4800:
                pb = await loop.run_in_executor(
                    None, self._stretch_pcm, pb, len(pb) / max(len(pa), 1)
                )
            xa = np.frombuffer(pa[: len(pa) // 2 * 2], dtype="<i2").astype(np.float32)
            xb = np.frombuffer(pb[: len(pb) // 2 * 2], dtype="<i2").astype(np.float32)
            n = max(len(xa), len(xb))
            xa = np.pad(xa, (0, n - len(xa)))
            xb = np.pad(xb, (0, n - len(xb)))
            t = (np.arange(n, dtype=np.float32) / NATIVE_SAMPLE_RATE) + self._duet_t
            p = 0.5 * (1.0 - np.cos(2.0 * np.pi * t / float(d["period_s"])))
            theta = p * (np.pi / 2.0) * float(d["depth"])
            mixed = (xa * np.cos(theta) + xb * np.sin(theta)) / 32768.0
            self._duet_t += n / NATIVE_SAMPLE_RATE
        data = np.clip(mixed, -1.0, 1.0).astype(np.float32).tobytes()
        step = 8192 * 4
        for i in range(0, len(data), step):
            yield data[i : i + step]

    async def stream_sentence(self, text: str) -> AsyncIterator[bytes]:
        """Synthesize one sentence, yielding float32 PCM as the engine produces it.

        The engine streams s16le at chunk granularity; this converts and hands
        each chunk straight on, so the first audio leaves for the client
        without waiting for the last. The duet path instead buffers the whole
        sentence (it needs both renditions to mix), costing well under a
        second of added lead time.
        """
        # Tags pass through whole: the strip that used to live here assumed
        # this engine reads stage directions aloud, and a listening test
        # (2026-08-08, Windows CUDA, Q8_0 weights) proved it PERFORMS them --
        # [laughter] laughs, arpabet brackets steer pronunciation. A sentence
        # that is nothing but a tag is a performance too, so it goes through.
        spoken = text.strip()
        if not spoken:
            return
        if self._duet:
            async for chunk in self._stream_duet(spoken):
                yield chunk
            return
        voice = self._voice or ""
        if self._cycle:
            voice = self._cycle[self._cycle_i % len(self._cycle)]
            self._cycle_i += 1
        payload = json.dumps(
            {"model": "omnivoice", "input": spoken, "voice": voice, "response_format": "pcm"}
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}/v1/audio/speech",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        loop = asyncio.get_running_loop()
        # Unbounded, deliberately. A bounded queue fed through
        # call_soon_threadsafe drops audio: the callbacks batch onto the event
        # loop and fire before the consuming coroutine is scheduled, so the
        # queue fills, put_nowait raises QueueFull inside the loop's callback,
        # and the exception is swallowed by the default handler. The stream
        # then simply stops mid-word with nothing in the log but a traceback
        # nobody is looking at -- which is how a voice says "I'm Sulivan" and
        # then goes quiet. The bound is the utterance instead: float32 at
        # 24 kHz is ~96 KB a second, and sentences are seconds long.
        queue: asyncio.Queue = asyncio.Queue()

        def _pump() -> None:
            try:
                with urllib.request.urlopen(req, timeout=300) as r:
                    tail = b""
                    while True:
                        chunk = r.read(8192)
                        if not chunk:
                            break
                        # s16le is two bytes a sample; a read can split one.
                        buf = tail + chunk
                        n = len(buf) - (len(buf) % 2)
                        tail = buf[n:]
                        if n:
                            pcm = np.frombuffer(buf[:n], dtype="<i2").astype(np.float32) / 32768.0
                            loop.call_soon_threadsafe(queue.put_nowait, pcm.tobytes())
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")[:200]
                loop.call_soon_threadsafe(queue.put_nowait, RuntimeError(f"engine {exc.code}: {detail}"))
            except Exception as exc:  # noqa: BLE001 - surfaced on the consuming side
                loop.call_soon_threadsafe(queue.put_nowait, exc)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        task = loop.run_in_executor(None, _pump)
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                yield item
        finally:
            await task
