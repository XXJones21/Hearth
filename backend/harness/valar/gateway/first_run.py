"""First-run detection, and what it changes.

The wiki's rule made concrete: the interview direction loads when the house
is factory-fresh, which means every non-internal persona is one that SHIPPED
(marked "shipped": true in its manifest). The moment create_persona writes a
new resident, the next turn's detection fails and everything here expires on
its own. No client flag to trust. (An engram-empty condition used to be part
of this and broke a reinstall over a lived-in root: the previous session's
thoughts made a factory-fresh backend read as lived-in, and the interview
ran with house tools and no direction. Residents are the signal; memory is
not.)

While first-run is active the default persona carries the direction appended
to its system prompt and a tool set narrowed to the interview: the measured
finding behind this (2026-08-07) is that seventeen tools and no direction
meant the interview tools were never chosen, even named explicitly.

The opening beat is scripted, not improvised. A 12B asked to open the
interview freely produced a different opener every run: permission-asking,
choosing its own first option for the person, promising cards it never
rendered. The walkthrough is product copy; the model enters at the person's
first answer. The client sends KICKOFF_SENTINEL and the voice loop speaks
OPENING_TEXT verbatim with OPENING_CARD beside it, no LLM turn at all.
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

# The client's stage direction for the interview's first beat. Matched
# exactly by is_kickoff; the client constant lives in setup/opener.ts and
# the two must stay identical.
KICKOFF_SENTINEL = "(Open the interview.)"

# The scripted walkthrough, spoken verbatim in Sulivan's voice. Same words
# every install: this is the product introducing its central idea, and the
# one question every persona starts from.
OPENING_TEXT = (
    "Let us make someone together. A persona is a companion of your own "
    "design who will live here with you: their purpose, their temperament, "
    "their voice, and their colour are all yours to choose. I will ask a "
    "few questions as we go, and your own words always beat my "
    "suggestions. First: what should this companion be for?"
)

OPENING_CARD: dict = {
    "version": 1,
    "type": "choice_card",
    "props": {
        "question": "What should this companion be for?",
        "options": [
            {"label": "A creative partner", "detail": "brainstorming, writing, ideas"},
            {"label": "A knowledge specialist", "detail": "research and deep answers"},
            {"label": "A personal coordinator", "detail": "plans, schedules, reminders"},
            {"label": "A warm companion", "detail": "company and conversation"},
        ],
        "allow_free_text": True,
    },
}


def is_kickoff(text: str) -> bool:
    return (text or "").strip() == KICKOFF_SENTINEL


# Sulivan's goodbye, spoken verbatim on the commit turn in place of whatever
# goodbye the model composed. Product copy, same rationale as OPENING_TEXT:
# the handover is the emotional peak of first run and should land the same
# way every install. After this is spoken the session switches to the new
# persona, who speaks next.
def farewell_text(name: str) -> str:
    return (
        f"{name} is ready, and from this moment the house is theirs: they "
        "will be the one who greets you from here on. I will step back now, "
        "but I am never far; call on me whenever you need me. It has been a "
        "pleasure making them with you."
    )


# ---------------------------------------------------------------------------
# Beat three: the second brain.
#
# Hosted by the persona just made, in their own voice, and argued from
# self-interest rather than features (wiki/first-run.md, "Beat three").
#
# It needs its own gating, and the reason is worth stating: `active()` below
# goes False the moment create_persona writes a resident, so by the time this
# beat runs first-run is over. On the normal path the new persona has the full
# tool set and no direction, which is exactly the condition measured on
# 2026-08-07 to produce zero interview-tool calls even when the tool was named
# explicitly. A beat that must end in one tool call cannot run there.
#
# So it is sentinel-gated rather than state-gated, the same shape as the
# interview's scripted opening: the client sends BRAIN_KICKOFF when it reaches
# the screen, and the beat holds until a project exists. Deriving it from state
# instead ("a resident exists and Projects is empty") would re-trigger months
# later for anyone who deletes their last project, which is the bug the engram-
# empty condition already caused once for first run.

BRAIN_KICKOFF = "(Open the second brain.)"

# The interview's tools would let the new persona create ANOTHER persona
# mid-beat. One tool, and the card that asks the question.
BRAIN_GRANTS: dict = {"domains": [], "allow": ["choice_card", "start_project"], "deny": []}

BRAIN_DIRECTION = (
    "SECOND BRAIN. This is the last beat of setup and you are hosting it, in "
    "your own voice, as the persona they just made. Three moves, in order, one "
    "per turn:\n"
    "1. Why it matters, from self-interest, not features: right now you will "
    "forget this conversation the moment it ends, and you would rather not.\n"
    "2. What it actually is: four plain folders on their own disk -- things "
    "with an end, things that never end, things worth keeping, and what was "
    "talked about by day. Readable in any text editor, deletable at any time, "
    "going nowhere.\n"
    "3. Ask what they are actually working on, and call start_project with "
    "their answer. Their own words, never a suggestion of yours, and never an "
    "example. One real thing beats an empty brain.\n"
    "Short turns. No lists of features. After start_project returns, say where "
    "it lives and stop."
)


def is_brain_kickoff(text: str) -> bool:
    return (text or "").strip() == BRAIN_KICKOFF


def brain_beat_open(engram_root) -> bool:
    """True while the second-brain beat still has work to do.

    Self-expiring, like first run: the beat is over when a project exists,
    because start_project writing one is the only way it ends. An unreadable
    or unconfigured root reports False -- a beat that cannot write is a beat
    that should not be run.
    """
    try:
        projects = Path(engram_root) / "Projects"
        return projects.is_dir() and not any(projects.iterdir())
    except Exception:  # noqa: BLE001 - unconfigured memory is not fatal
        return False


# The voice test's fixed query (VoiceTest.tsx GREETING_QUERY); prefix-matched
# so the greeting turn stays on the normal streaming path with the small
# direction below, while every other first-run turn goes structured.
VOICE_CHECK_PREFIX = "(I have just finished installing you"


def is_voice_check(text: str) -> bool:
    return (text or "").strip().startswith(VOICE_CHECK_PREFIX)


# What the greeting turn needs and nothing more. The full interview direction
# describes the structured reply form, which would contaminate a free-prose
# greeting.
GREETING_DIRECTION = (
    "FIRST RUN. This machine was installed today and the message in "
    "parentheses is the voice test: introduce yourself in two or three short "
    "sentences and mention that if they can hear your voice, everything is "
    "working. No questions, no tools, and not a word about personas."
)


# The structured interview turn: every reply is this object, enforced as a
# grammar by llama-server. `speech` is spoken aloud; `question` + `options`
# become the choice card; `commit` stays null until the persona is ready.
INTERVIEW_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "speech": {"type": "string"},
        "question": {"type": "string"},
        "options": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "label": {"type": "string"},
                    "detail": {"type": "string"},
                },
                "required": ["label", "detail"],
            },
        },
        "commit": {
            "anyOf": [
                {"type": "null"},
                {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "description": {"type": "string"},
                        "system_prompt": {"type": "string"},
                        "temperament": {"type": "string"},
                        "voice_design": {"type": "array", "items": {"type": "string"}},
                        "colour": {"type": "string"},
                    },
                    "required": [
                        "name",
                        "description",
                        "system_prompt",
                        "temperament",
                        "voice_design",
                        "colour",
                    ],
                },
            ]
        },
    },
    "required": ["speech", "question", "options", "commit"],
}

_DIRECTION_PATH = Path(__file__).resolve().parents[1] / "data" / "first_run_direction.md"

_cache: dict = {"at": 0.0, "active": False}
_CACHE_TTL_S = 3.0


def direction_text() -> str:
    try:
        return _DIRECTION_PATH.read_text(encoding="utf-8").strip()
    except OSError as exc:
        logger.warning("first-run direction missing (%s); interview runs bare", exc)
        return ""


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
    state = _all_personas_shipped(persona_dir)
    _cache.update(at=now, active=state)
    return state
