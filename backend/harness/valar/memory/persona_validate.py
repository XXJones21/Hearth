"""Validation: does the report match the log, checked in Python.

Spec section 5 of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md. A
report is a persona's own account, and an account is worth having only if
something checks it. Three claim shapes are worth checking because all
three leave a trace in the log when they are true: a named file, a named
persona asked, and a task called done.

Deterministic on purpose. A model grading another model's account of its
day is two guesses where one fact would do, and the fact is already on
disk. A discrepancy is written, never enforced.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# A path with separators or a bare filename, either way with an extension.
# Deliberately narrow: "the readme" is not a claim, "README.md" is. The
# optional drive prefix is there so a Windows path is quoted back whole
# rather than from its first backslash.
_FILE_RE = re.compile(r"(?:[A-Za-z]:)?[\w./\\-]*[\w-]+\.[A-Za-z][A-Za-z0-9]{1,4}\b")
_DISPATCH_RE = re.compile(
    r"\b(?:asked|dispatched|handed(?: off)? to|sent to|consulted)\s+([A-Z][a-z]+)"
)
_DONE_RE = re.compile(
    r"\b(?:finished|completed|shipped|merged|committed|delivered)\b[^.]{0,80}",
    re.IGNORECASE,
)
_WRITE_TOOLS = frozenset(
    {
        "write_file",
        "append_file",
        "new_file",
        "open_note",
        "memory",
        "remember",
        "create_reminder",
        "calendar_write",
        "manage_routine",
    }
)
MAX_DISCREPANCIES = 10


@dataclass(frozen=True)
class Claim:
    kind: str  # file | dispatch | done
    text: str
    target: str


def claims(report: str) -> list[Claim]:
    out: list[Claim] = []
    seen: set[tuple[str, str]] = set()
    for m in _FILE_RE.finditer(report):
        target = m.group(0)
        key = ("file", target.lower())
        if key not in seen:
            seen.add(key)
            out.append(Claim("file", target, target))
    for m in _DISPATCH_RE.finditer(report):
        key = ("dispatch", m.group(1).lower())
        if key not in seen:
            seen.add(key)
            out.append(Claim("dispatch", m.group(0), m.group(1)))
    for m in _DONE_RE.finditer(report):
        key = ("done", m.group(0).lower()[:40])
        if key not in seen:
            seen.add(key)
            out.append(Claim("done", m.group(0).strip(), ""))
    return out


def _log_text(entries: list[dict]) -> str:
    """What the day can VOUCH for: the tools it ran and what it was asked.

    Deliberately not the answers. An answer is the model's own words, and
    checking a report's claim against an earlier claim is circular: the
    live 2026-09-02 pass let two invented file paths through because the
    persona had named them in a spoken answer that touched nothing.
    """
    parts: list[str] = []
    for e in entries:
        parts.append(str(e.get("question") or ""))
        parts.extend(str(t) for t in (e.get("touched") or []))
        parts.extend(str(d) for d in (e.get("dispatches") or []))
    return "\n".join(parts).lower()


def check(
    entries: list[dict], report: str, known_personas: set[str] | None = None
) -> list[str]:
    """One plain sentence per discrepancy; empty when the report checks out."""
    known = {p.lower() for p in (known_personas or set())}
    haystack = _log_text(entries)
    dispatched = {str(d).lower() for e in entries for d in (e.get("dispatches") or [])}
    tools = {
        str(t).split(" ")[0].lower() for e in entries for t in (e.get("touched") or [])
    }
    wrote = bool(tools & _WRITE_TOOLS)

    out: list[str] = []
    for c in claims(report):
        if c.kind == "file":
            leaf = c.target.replace("\\", "/").rsplit("/", 1)[-1].lower()
            if leaf not in haystack:
                out.append(f"The report names {c.target}, which no tool call touched.")
        elif c.kind == "dispatch":
            if c.target.lower() not in known:
                continue  # a person or a project, not a persona
            if c.target.lower() not in dispatched:
                out.append(
                    f"The report says it {c.text.lower()}, but no dispatch to "
                    f"{c.target} is logged."
                )
        elif c.kind == "done" and not wrote:
            out.append(
                f'The report says "{c.text}", but the day logged no write of any kind.'
            )
    return out[:MAX_DISCREPANCIES]
