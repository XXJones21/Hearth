"""Per-connection session state: the IDLE->LISTENING->THINKING->SPEAKING machine,
the audio buffer for server-side STT, and bounded conversation history.

History is kept in full per session (no destructive truncation); the context
assembler decides how much to send per turn under the sane token budget.
"""

from __future__ import annotations

import enum
import time
from dataclasses import dataclass, field

from .context import Turn


class State(enum.Enum):
    IDLE = "idle"
    LISTENING = "listening"
    THINKING = "thinking"
    SPEAKING = "speaking"


@dataclass
class Session:
    session_id: str
    platform: str = "unknown"
    stt_mode: str = "server"  # "server" | "local"
    # How the current turn arrived: "voice" (an utterance) or "text" (a typed
    # query or client transcription). Read by the persona-memory log so a
    # turn's origin is recorded, never inferred.
    last_input: str = "voice"
    audio_format: dict = field(default_factory=dict)
    state: State = State.IDLE
    history: list[Turn] = field(default_factory=list)
    audio_buffer: bytearray = field(default_factory=bytearray)
    # Ambient device/environment context the client supplies from its OS:
    # {timezone, locale, units, location: {city, region, lat, lon}, client_time}.
    # Injected into the prompt every turn (the SCX "Current context" block) so the
    # brain always knows the time/place without a tool call. Merged from client_info
    # (static-ish: tz/locale/location) and refreshed per turn where the path allows.
    device_context: dict = field(default_factory=dict)
    # Client capabilities from the client_info handshake (dict of truthy flags,
    # e.g. {"ui_render": true, "device_actions": true}). Gates which catalog
    # tools are offered this session: a tool with `requires_capability` is only
    # offered when the client advertises that key. Empty = any-client tools only.
    capabilities: dict = field(default_factory=dict)
    # Monotonic timestamp of the last completed turn (or session start) — the
    # idle watchdog's clock for the auto session-end.
    last_activity: float = field(default_factory=time.monotonic)
    # Turn epoch: bumped by `reset_vad` (the client abandoned the turn, e.g. its
    # conversation timeout fired). An utterance captures the epoch at VAD end;
    # if it changed by the time STT returns, the turn is stale and is DROPPED
    # instead of answering a conversation the client already left (2026-06-06:
    # a 31s first-inference STT outlived the client timeout and produced
    # overlapping zombie turns).
    turn_epoch: int = 0
    # The in-flight STT+turn task (Phase B, 2026-06-06): the voice turn runs as
    # a per-session asyncio.Task so the WS receive loop stays responsive — an
    # in-band `reset_vad` can now CANCEL the turn instead of queueing behind it,
    # and a disconnect cancels it instead of letting it emit into a dead socket.
    turn_task: object | None = None
    # Engram topic for this chat (project or life-root name). Passed into
    # memory.recall so every turn loads that claude.md. Cleared on session end.
    topic_hint: str | None = None
    # The persona's private block, built once per session per persona and
    # reused (snapshot, never volatile). Cleared when the session ends;
    # rebuilt when the speaking persona changes.
    memory_block: str = ""
    memory_block_persona: str = ""
    # Leftover file work from tool_loop.carry (list_dir files not yet read).
    # Mechanical, not spoken history. Survives session end; retired on TTL.
    open_task: dict | None = None
    # Fold digests: what the files already read actually said. History keeps
    # only the spoken sentence, so without this the knowledge from a 24-file
    # sweep evaporates at turn end and the next utterance re-reads the tree.
    task_notes: list[str] = field(default_factory=list)
    # When the newest digest was written, for the notes' own expiry. The
    # remainder and the notes retire separately: the remainder carries an
    # INSTRUCTION ("read these now") that must not leak into an unrelated
    # turn, while the notes are inert knowledge worth keeping through a
    # detour ("what did you find?" then "now write it up").
    task_notes_at: float = 0.0
    # Destination note opened by the open_note tool. Each folded batch is
    # appended here as it is read, so the file on disk is the durable record
    # rather than in-memory state a restart can lose.
    task_dest: str = ""

    def record_turn(self, user: str, assistant: str, persona: str = "") -> None:
        self.history.append(Turn(user=user, assistant=assistant))
        # Durable as it happens, not at session end. This is the one seam every
        # completed exchange passes through, which is why the record hangs
        # here rather than in the three places sessions can end.
        try:
            from ..memory.session_record import append_turn

            append_turn(self, user, assistant, persona)
        except Exception:  # noqa: BLE001 - recording never breaks a turn
            pass
        self.touch()

    def touch(self) -> None:
        self.last_activity = time.monotonic()

    def reset_audio(self) -> None:
        self.audio_buffer = bytearray()
