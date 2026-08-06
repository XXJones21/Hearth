"""Incremental sentence segmenter for the streaming voice loop.

Accumulates brain token deltas and emits complete sentences as soon as a
terminal boundary (. ! ? newline) is seen, so TTS can begin speaking the first
sentence while the brain is still generating the rest. A small minimum length
avoids cutting on abbreviations / decimals producing tiny fragments.
"""

from __future__ import annotations

import re

_BOUNDARY = re.compile(r"([.!?]+[\"')\]]?\s+|\n{1,})")


class SentenceSegmenter:
    def __init__(self, min_chars: int = 12):
        self.min_chars = min_chars
        self._buf = ""

    def feed(self, delta: str) -> list[str]:
        """Add a token delta; return any complete sentences now available."""
        self._buf += delta
        out: list[str] = []
        while True:
            match = _BOUNDARY.search(self._buf)
            if not match:
                break
            end = match.end()
            candidate = self._buf[:end].strip()
            # Avoid emitting trivially short fragments (e.g. "Dr.").
            if len(candidate) < self.min_chars and match.group(1).strip() in (".",):
                # extend search past this boundary
                nxt = _BOUNDARY.search(self._buf, end)
                if not nxt:
                    break
                end = nxt.end()
                candidate = self._buf[:end].strip()
            if candidate:
                out.append(candidate)
            self._buf = self._buf[end:]
        return out

    def flush(self) -> str | None:
        """Return any trailing text not terminated by a boundary."""
        leftover = self._buf.strip()
        self._buf = ""
        return leftover or None
