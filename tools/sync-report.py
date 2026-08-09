#!/usr/bin/env python3
"""What has changed in Valinor's shipping set since Hearth copied it.

The migration window is days long and Valinor keeps receiving commits during
it, because it is the daily driver. This reads backend/manifest.yaml, asks the
Valinor repository what has touched each source path since the copy, and
prints it.

It REPORTS. It never copies. An automatic re-sync would clobber the de-literal
edits, which are the entire value produced by the migration, so the correct
response to a non-empty report is to hand-port the change. If the report is
non-empty twice, the window is too long; that is a scheduling answer, not a
tooling one.

Usage:
    tools/sync-report.py [--valinor PATH] [--since TAG] [--quiet]

    --valinor  the Valinor checkout. Default: $VALINOR_REPO, then D:/Tools/Valinor
    --since    the tag or commit to compare from. Default: the manifest's
               source.commit, which is what was actually copied. The tag is
               the rollback point and is deliberately NOT the default: three
               commits landed between the two.
    --quiet    print nothing when there is no drift; exit 0 either way

Exit status is 0 when there is no drift and 1 when there is, so it can gate a
release step without anyone reading it.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "backend" / "manifest.yaml"


def source_paths(manifest: dict) -> list[str]:
    """Every path in Valinor the manifest claims to have copied.

    Components with disposition `generated` have no source and are skipped;
    excluded entries are included deliberately, because a change to something
    we chose not to ship is worth seeing even though it will not be ported.

    Two manifests are in play and they spell things differently. The backend's
    writes repository-relative paths and names per-file entries `source`. The
    Apple one factors the common prefix out into `source.root` and names
    per-file entries `from`, because a flat list of 79 paths that all begin
    `Apple Client/Valinor/Valinor/` is a worse document. Both are read here, and
    a path that already starts with the root is not given a second one.
    """
    root = ((manifest.get("source") or {}).get("root") or "").rstrip("/")
    paths: set[str] = set()

    def add(value, prefix: str = "") -> None:
        if not isinstance(value, str) or not value or value == "null":
            return
        path = f"{prefix.rstrip('/')}/{value}" if prefix else value
        if root and not path.startswith(f"{root}/"):
            path = f"{root}/{path}"
        paths.add(path.rstrip("/"))

    for component in manifest.get("components") or []:
        base = component.get("source")
        add(base)
        for entry in component.get("files") or []:
            if isinstance(entry, dict):
                add(entry.get("source") or entry.get("from"), base or "")
    for entry in manifest.get("excluded") or []:
        value = entry.get("source")
        for one in [value] if isinstance(value, str) else (value or []):
            add(one)
    return sorted(paths)


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed in {repo}:\n{result.stderr.strip()}")
    return result.stdout


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--valinor")
    ap.add_argument("--since")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument(
        "--manifest",
        help="the manifest to read. Default: backend/manifest.yaml. "
        "The Apple migration passes apple-client/manifest.yaml.",
    )
    args = ap.parse_args()

    try:
        import yaml
    except ImportError:
        raise SystemExit("this needs pyyaml: pip install pyyaml") from None

    manifest_path = Path(args.manifest) if args.manifest else MANIFEST
    if not manifest_path.is_absolute():
        manifest_path = REPO / manifest_path
    if not manifest_path.exists():
        raise SystemExit(f"no manifest at {manifest_path}")
    manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    # source.path is the manifest's own answer to "where is Valinor", which the
    # backend manifest predates. It comes after the flag and the environment and
    # before the historical Windows default.
    valinor = Path(
        args.valinor
        or os.environ.get("VALINOR_REPO")
        or (manifest.get("source") or {}).get("path")
        or "D:/Tools/Valinor"
    ).expanduser()
    if not (valinor / ".git").exists():
        raise SystemExit(f"no git repository at {valinor}; pass --valinor")

    source = manifest.get("source") or {}
    since = args.since or source.get("commit") or source.get("tag")
    if not since:
        raise SystemExit("the manifest names no source.commit and --since was not given")
    git(valinor, "rev-parse", "--verify", f"{since}^{{commit}}")

    paths = source_paths(manifest)
    log = git(
        valinor,
        "log",
        "--no-merges",
        "--format=%h %ad %s",
        "--date=short",
        f"{since}..HEAD",
        "--",
        *paths,
    ).strip()

    if not log:
        if not args.quiet:
            print(
                f"No drift. Nothing under the shipping set has changed in "
                f"{valinor} since {since} ({len(paths)} paths checked)."
            )
        return 0

    commits = log.splitlines()
    print(f"DRIFT: {len(commits)} commit(s) touched the shipping set since {since}.")
    print(f"Repository: {valinor}\n")
    for line in commits:
        print(f"  {line}")

    print("\nFiles:")
    files = git(
        valinor, "diff", "--name-only", f"{since}..HEAD", "--", *paths
    ).strip()
    for name in sorted(set(files.splitlines())):
        print(f"  {name}")

    print(
        "\nHand-port anything above that belongs to a component the manifest "
        "marks `verbatim` or `edits`. Do not re-run the copy: it would discard "
        "the de-literal work."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
