"""A tool call the model WROTE instead of made.

The Gemma 4 dialect wants a sentinel pair:

    <|tool_call>call:close_room{room:<|"|>slug<|"|>,...}<tool_call|>

Intermittently the 12B drops out of that and emits generic function-call
notation into the body instead:

    call close_room(room_id="hearth-launch-copy", summary="...")

No sentinels, parentheses for braces, `=` for `:`, plain quotes. Nothing
parses it, nothing runs, and the turn is recorded as a claim with an empty
receipt. Measured 2026-09-03 across the room transcripts: 3 of 141 persona
turns, one from each persona, three different tools. In the clearest of the
three every argument matched the schema exactly, so this is an emission
fault and not a comprehension one.

There is precedent for recovering this model's dialect drift rather than
re-prompting it: prompt_format.py already carries a recovery for the 12B
omitting the <|"|> delimiters around Windows paths (2026-08-16).

WHAT THIS DELIBERATELY REFUSES. Executing text a model wrote as prose is a
different contract from executing a call it made, so the narrowing is the
whole design:

- only when the response carried NO real tool calls, so a real call always
  wins and this can never add to one;
- only a tool the caller already holds, so it can never reach past the grant
  the persona was given;
- only when EVERY required parameter is present after light normalisation.
  No positional guessing: the live Soth case wrote
  assign_task(task_id=, actor=, description=) and salvaging that by position
  would have created a task whose room was "t3". It is refused instead, which
  is the correct outcome for arguments that are genuinely wrong;
- and the call text is cut from the content, so a salvaged call is not also
  spoken and posted as prose.

Task: tasks/development/prose-tool-calls.md
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

logger = logging.getLogger("valar.tools.salvage")

# name( ... ) with an optional "call " lead. The parentheses are load-bearing:
# they are what separates a call from a mention, so "call assign_task when you
# are ready" and "I could use assign_task here" never match.
_CALL_RE = re.compile(
    r"(?:^|\n)[ \t]*(?:call[ \t]+)?([a-z_][a-z0-9_]{2,40})[ \t]*\(([^()]{0,4000})\)",
    re.IGNORECASE,
)

# key = "value" | 'value' | bare token. Escaped quotes inside a value survive.
_ARG_RE = re.compile(
    r"""([a-z_][a-z0-9_]*)\s*[=:]\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^,\s)]+))""",
    re.IGNORECASE,
)


def _normalise(key: str) -> str:
    """The only renaming allowed, and it is conservative on purpose.

    Stripping a trailing _id recovers the live Sulivan case, close_room's
    room_id for room. Anything further would be guessing: actor for assignee
    and description for text are NOT derivable, and a rule loose enough to
    catch them is loose enough to put a value in the wrong field.
    """
    key = key.strip().lower()
    if key.endswith("_id") and len(key) > 3:
        return key[:-3]
    return key


def _params(schema: dict) -> tuple[set[str], set[str]]:
    """(all parameter names, required names) from one registry schema."""
    fn = schema.get("function") if "function" in schema else schema
    params = (fn or {}).get("parameters") or {}
    props = set((params.get("properties") or {}).keys())
    required = set(params.get("required") or [])
    return props, required


def salvage_calls(
    content: str,
    schemas: list[dict],
) -> tuple[list[dict[str, Any]], str]:
    """Recover written calls from ``content``. Returns (tool_calls, content).

    ``schemas`` is exactly what the registry offered the model this round, so
    the grant is enforced by construction: a tool the persona was not given is
    not in the list and cannot be salvaged.

    The returned content has every salvaged call cut out of it. Anything not
    salvaged is left where it is, so a refusal stays visible to the operator
    rather than being silently swallowed.
    """
    if not content or not schemas:
        return [], content

    known = {}
    for s in schemas:
        fn = s.get("function") if "function" in s else s
        name = (fn or {}).get("name") or ""
        if name:
            known[name] = _params(s)
    if not known:
        return [], content

    calls: list[dict[str, Any]] = []
    cuts: list[tuple[int, int]] = []

    for m in _CALL_RE.finditer(content):
        name, body = m.group(1), m.group(2)
        if name not in known:
            continue
        props, required = known[name]

        args: dict[str, Any] = {}
        for a in _ARG_RE.finditer(body):
            key = _normalise(a.group(1))
            val = a.group(2) or a.group(3) or a.group(4) or ""
            if key in props:
                args[key] = val.replace('\\"', '"').replace("\\'", "'")

        missing = required - set(args)
        if missing:
            logger.info(
                "salvage refused: %s written as prose but missing %s",
                name,
                sorted(missing),
            )
            continue

        calls.append(
            {
                "id": f"salvaged_{len(calls) + 1}",
                "type": "function",
                "function": {"name": name, "arguments": json.dumps(args)},
            }
        )
        cuts.append((m.start(), m.end()))
        logger.warning(
            "SALVAGED a written tool call: %s(%s). The model emitted this as "
            "prose instead of a tool call; see tasks/development/"
            "prose-tool-calls.md",
            name,
            ", ".join(sorted(args)),
        )

    if not calls:
        return [], content

    out = content
    for start, end in reversed(cuts):
        out = out[:start] + out[end:]
    return calls, out.strip()
