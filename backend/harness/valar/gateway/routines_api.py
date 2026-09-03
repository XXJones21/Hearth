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
from datetime import datetime
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

# A draft is any .md the persona wrote into the drafts folder: a safe basename,
# no path parts. Approve and reject only ever MOVE files between the folder's
# own subdirectories; nothing is deleted and nothing is published.
_DRAFT_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.md$")
_DRAFT_EXCERPT_CHARS = 600


def _drafts_dir() -> Path:
    return _repo_root() / "tasks" / "GTM" / "content" / "drafts"


def _list_drafts() -> list[dict]:
    out: list[dict] = []
    root = _drafts_dir()
    if not root.is_dir():
        return out
    for md in sorted(root.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True):
        if md.name.lower() == "readme.md":
            continue
        try:
            text = md.read_text(encoding="utf-8")
            stamp = datetime.fromtimestamp(md.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        except OSError:
            continue
        out.append({"name": md.name, "at": stamp, "excerpt": text[:_DRAFT_EXCERPT_CHARS]})
    return out


def register(app, config) -> None:
    @app.get("/routines/feed")
    async def routines_feed() -> dict:
        try:
            return {"routines": _roster(config), "feed": _feed()}
        except Exception as exc:  # noqa: BLE001 - the rail never gets a 500
            logger.warning("routines feed failed: %s", exc)
            return {"routines": [], "feed": []}

    @app.get("/routines/drafts")
    async def routines_drafts() -> dict:
        try:
            return {"drafts": _list_drafts()}
        except Exception as exc:  # noqa: BLE001
            logger.warning("drafts list failed: %s", exc)
            return {"drafts": []}

    @app.post("/routines/drafts/act")
    async def routines_drafts_act(payload: dict) -> dict:
        """Approve or reject one draft. Approve moves it to drafts/approved/,
        cleared for the operator to publish by hand; reject moves it to
        drafts/rejected/ with the reason appended so the next draft learns
        from it. Publishing itself never happens here."""
        name = str((payload or {}).get("name") or "")
        verdict = str((payload or {}).get("action") or "")
        reason = str((payload or {}).get("reason") or "").strip()
        if not _DRAFT_NAME_RE.match(name) or verdict not in ("approve", "reject"):
            return {"ok": False, "error": "bad name or action"}
        src = _drafts_dir() / name
        if not src.is_file():
            return {"ok": False, "error": "no such draft"}
        dest_dir = _drafts_dir() / ("approved" if verdict == "approve" else "rejected")
        try:
            if verdict == "reject":
                stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
                with src.open("a", encoding="utf-8", newline="\n") as fh:
                    fh.write(f"\n\n---\nRejected {stamp}: {reason or 'no reason given'}\n")
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / name
            if dest.exists():
                dest = dest_dir / f"{src.stem}-{datetime.now().strftime('%H%M%S')}{src.suffix}"
            src.replace(dest)
            return {"ok": True, "moved_to": dest.relative_to(_repo_root()).as_posix()}
        except OSError as exc:
            logger.warning("draft %s %s failed: %s", verdict, name, exc)
            return {"ok": False, "error": str(exc)}

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
