"""The routines feed: what the house does on its own clock, made visible.

The honest gap, closed one notch: the house has no proactive push channel, so
routine runs used to land only as files in the tracker. This surface lets the
client's Routines rail read them: the routine roster (from Persona/*/
routines.yaml plus each routine's switch state in Engram/Areas/routines.md)
and a feed built from the artifacts the runs already write, report files and
runlog lines. Nothing new is recorded here; the feed IS the files, read back.
The client polls; a push seam can replace the poll later without changing the
payload shape.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

logger = logging.getLogger("valar.routines_api")

_FEED_CAP = 30
_EXCERPT_CHARS = 400
_RUNLOG_RE = re.compile(r"^-\s*(?P<at>\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s+(?P<text>.+)$")


def _repo_root() -> Path:
    """Under the Valinor overlay HEARTH_HOME is the Valinor checkout, where
    the tracker tree lives. Vanilla installs return empty feeds."""
    from ..config.settings import hearth_home

    return Path(hearth_home())


def _runs_dir() -> Path:
    return _repo_root() / "tasks" / "GTM" / "content" / "runs"


def _roster(config) -> list[dict]:
    from ..agents.soth_routine import load_routines, routine_enabled, _load_state

    state = _load_state()
    out = []
    for r in load_routines(Path(config.persona_dir)):
        title = str(r.get("title") or r.get("name"))
        out.append(
            {
                "name": str(r.get("name")),
                "title": title,
                "persona": str(r.get("persona")),
                "schedule": str(r.get("schedule") or ""),
                "enabled": routine_enabled(title),
                "last_success_at": str(state.get("last_success_at") or ""),
                "failure_streak": int(state.get("failure_streak") or 0),
            }
        )
    return out


def _feed() -> list[dict]:
    entries: list[dict] = []
    runs = _runs_dir()
    for report in runs.glob("*_soth.md"):
        try:
            text = report.read_text(encoding="utf-8")
        except OSError:
            continue
        body = text.split("\n", 1)[1] if "\n" in text else text
        stamp = report.stem.replace("_soth", "").replace("_", " ")
        entries.append(
            {
                "at": f"{stamp[:10]} {stamp[11:13]}:{stamp[13:15]}",
                "routine": "soth-daily",
                "kind": "report",
                "path": report.relative_to(_repo_root()).as_posix(),
                "excerpt": body.strip()[:_EXCERPT_CHARS],
            }
        )
    runlog = runs / "runlog.md"
    if runlog.exists():
        try:
            for ln in runlog.read_text(encoding="utf-8").splitlines():
                m = _RUNLOG_RE.match(ln.strip())
                if not m:
                    continue
                text = m.group("text")
                if text.startswith("report written"):
                    continue  # the report entry above already carries it
                entries.append(
                    {
                        "at": m.group("at"),
                        "routine": "soth-daily",
                        "kind": "failure" if "FAILED" in text else "skip",
                        "path": "",
                        "excerpt": text[:_EXCERPT_CHARS],
                    }
                )
        except OSError:
            pass
    entries.sort(key=lambda e: e["at"], reverse=True)
    return entries[:_FEED_CAP]


# A report name is exactly what the routine writes, nothing else reaches disk.
_REPORT_NAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_\d{4}_[a-z]+\.md$")


def register(app, config) -> None:
    @app.get("/routines/feed")
    async def routines_feed() -> dict:
        try:
            return {"routines": _roster(config), "feed": _feed()}
        except Exception as exc:  # noqa: BLE001 - the rail never gets a 500
            logger.warning("routines feed failed: %s", exc)
            return {"routines": [], "feed": []}

    @app.get("/routines/report/{name}")
    async def routines_report(name: str) -> dict:
        """The full report behind one feed entry, for the click-to-open
        detail. The name is validated against the exact shape the routine
        writes; anything else is not a path, it is a refusal."""
        if not _REPORT_NAME_RE.match(name):
            return {"ok": False, "content": ""}
        path = _runs_dir() / name
        try:
            return {"ok": True, "content": path.read_text(encoding="utf-8")}
        except OSError:
            return {"ok": False, "content": ""}
