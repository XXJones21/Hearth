"""Dev work enters the inbox: the git-commit harvester.

Thoughts is the inbox for everything the house experiences, and the nightly
review is the librarian that reads it. Voice sessions file themselves; dev
work never did, so a day spent on a feature branch was invisible to "what
did we do yesterday". This module files it: for each configured repo, one
diary per day at ``Thoughts/<day>-dev-<slug>/claude.md`` listing that day's
commits, written raw and deterministic so the review summarizes it exactly
the way it summarizes any other diary.

The configuration is the plain-text record (``Areas/routines.md``): lines of
the form ``- <repo-path> -> <project-slug>`` under a **Dev sources** entry.
Delete a line and that repo stops being harvested; no list means no
harvesting at all, so an install without repos behaves exactly as before.

One review clock per brain: this module harvests, it never reviews. The
CLI exists for the one-time backfill and for manual runs from the Valinor
testbed; the ongoing call belongs at the top of the review clock's
pending-day loop (the Hearth port).

Spec: tasks/dev-work-ingestion.md.
"""

from __future__ import annotations

import argparse
import logging
import re
import subprocess
from datetime import date, timedelta
from pathlib import Path

logger = logging.getLogger("valar.memory.dev_harvest")

# `- D:/Tools/Valinor -> valinor` (list marker optional so a hand-edited
# record without one still counts; the arrow is the signature).
_SOURCE_LINE_RE = re.compile(r"^\s*-?\s*(.+?)\s*->\s*([A-Za-z0-9][\w-]*)\s*$")

_GIT_TIMEOUT_S = 30
_MAX_COMMITS_PER_DIARY = 60


def dev_sources(root: Path) -> list[tuple[Path, str]]:
    """(repo_path, project_slug) pairs from the routines record. Only lines
    whose path is a real git repo count, so prose never parses as a source."""
    record = Path(root) / "Areas" / "routines.md"
    try:
        text = record.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    out: list[tuple[Path, str]] = []
    for line in text.splitlines():
        m = _SOURCE_LINE_RE.match(line)
        if not m:
            continue
        repo = Path(m.group(1).strip().strip("`"))
        if (repo / ".git").exists():
            out.append((repo, m.group(2)))
    return out


def _git(repo: Path, *args: str) -> str:
    """One git call, empty string on any failure -- a bad repo never breaks
    the pass."""
    try:
        r = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True, text=True, timeout=_GIT_TIMEOUT_S,
        )
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.warning("git failed in %s: %s", repo, exc)
        return ""


def _day_commits(repo: Path, day: str) -> tuple[list[str], set[str], str]:
    """(commit lines, branch names, totals line) for one repo and one day."""
    span = [f"--since={day} 00:00:00", f"--until={day} 23:59:59"]
    log = _git(
        repo, "log", "--all", "--source", *span,
        "--format=%h|%S|%s",
    )
    commits: list[str] = []
    branches: set[str] = set()
    for line in log.splitlines():
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        short, ref, subject = parts
        ref = ref.removeprefix("refs/heads/").removeprefix("refs/remotes/")
        if ref and not ref.startswith("refs/"):
            branches.add(ref)
        commits.append(f"- {subject} ({short})")
        if len(commits) >= _MAX_COMMITS_PER_DIARY:
            commits.append("- ... (further commits elided)")
            break
    stats = _git(repo, "log", "--all", *span, "--shortstat", "--format=")
    files = ins = dels = 0
    for m in re.finditer(
        r"(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?",
        stats,
    ):
        files += int(m.group(1))
        ins += int(m.group(2) or 0)
        dels += int(m.group(3) or 0)
    n = len([c for c in commits if not c.endswith("elided)")])
    totals = (
        f"{n} commit(s), {files} file change(s), "
        f"+{ins}/-{dels} lines"
    )
    return commits, branches, totals


def harvest_day(root: Path, day: str, sources: list[tuple[Path, str]] | None = None) -> int:
    """File one dev diary per source repo with commits on ``day``. Returns
    the number of diaries written. Idempotent: an existing folder for a repo
    and day is never rewritten. Never raises."""
    try:
        srcs = dev_sources(root) if sources is None else sources
        written = 0
        for repo, slug in srcs:
            folder = Path(root) / "Thoughts" / f"{day}-dev-{slug}"
            if folder.exists():
                continue
            commits, branches, totals = _day_commits(repo, day)
            if not commits:
                continue
            body = "\n".join(
                [
                    f"# Dev work: {slug} ({day})",
                    "",
                    f"project: {slug}",
                    f"branches: {', '.join(sorted(branches)) or 'unknown'}",
                    "",
                    *commits,
                    "",
                    totals,
                    "",
                ]
            )
            try:
                folder.mkdir(parents=True, exist_ok=True)
                (folder / "claude.md").write_text(body, encoding="utf-8")
            except OSError as exc:
                logger.warning("dev diary write failed for %s: %s", folder, exc)
                continue
            written += 1
            logger.info("dev diary: %s (%s)", folder.name, totals)
        return written
    except Exception:  # noqa: BLE001 - harvesting never breaks the caller
        logger.exception("dev harvest failed for %s", day)
        return 0


def _default_root() -> Path:
    try:
        from .journal_sync import engram_root

        root = engram_root()
        if root is not None:
            return root
    except Exception:  # noqa: BLE001
        pass
    return Path(__file__).resolve().parents[3] / "Engram"


def main() -> None:
    p = argparse.ArgumentParser(description="File dev diaries from git history.")
    p.add_argument("--root", type=Path, default=None, help="Engram root")
    p.add_argument("--day", help="one day, YYYY-MM-DD")
    p.add_argument("--since", help="range start, YYYY-MM-DD")
    p.add_argument("--until", help="range end inclusive, YYYY-MM-DD")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    root = args.root or _default_root()
    srcs = dev_sources(root)
    if not srcs:
        print(f"no dev sources configured in {root}/Areas/routines.md")
        return
    if args.day:
        days = [args.day]
    elif args.since and args.until:
        d0, d1 = date.fromisoformat(args.since), date.fromisoformat(args.until)
        days = [
            (d0 + timedelta(days=i)).isoformat()
            for i in range((d1 - d0).days + 1)
        ]
    else:
        days = [(date.today() - timedelta(days=1)).isoformat()]
    total = 0
    for day in days:
        total += harvest_day(root, day, srcs)
    print(f"{total} dev diary(ies) written under {root}/Thoughts")


if __name__ == "__main__":
    main()
