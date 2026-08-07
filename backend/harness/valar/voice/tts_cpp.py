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

    def sync_persona_voice(self, ref_audio: Optional[Path], ref_text: Optional[str]) -> None:
        """Resolve the persona to a voice the engine already holds.

        ref_text is unused: the engine was given the transcript alongside the
        clip at startup. It stays in the signature because the seam above is
        shared with the torch engine, which does need it.
        """
        name = self.voice_name_for(ref_audio)
        body = self._get_json("/v1/voices")
        self._seen_healthy = True
        available = [v.get("name") for v in (body.get("voices") or []) if isinstance(v, dict)]
        if name and name in available:
            self._voice = name
            logger.info("voice '%s' resolved on the engine", name)
            return
        raise RuntimeError(
            f"the voice engine has no voice named {name!r} (it offers {available or 'none'}). "
            "tts-server is started with --voice <name>:<clip.wav>:<transcript.txt> per persona."
        )

    # --- synthesis ----------------------------------------------------------

    async def stream_sentence(self, text: str) -> AsyncIterator[bytes]:
        """Synthesize one sentence, yielding float32 PCM as the engine produces it.

        The engine streams s16le at chunk granularity; this converts and hands
        each chunk straight on, so the first audio leaves for the client
        without waiting for the last.
        """
        payload = json.dumps(
            {"model": "omnivoice", "input": text, "voice": self._voice or "", "response_format": "pcm"}
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
