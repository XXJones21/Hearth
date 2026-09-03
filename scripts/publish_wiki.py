#!/usr/bin/env python3
"""Render wiki/ into the GitHub wiki (Hearth.wiki.git).

The in-repo wiki is the source; the GitHub wiki is derived from it and is
never edited by hand. This script is what keeps them in sync, run by the
publish-wiki workflow on every push to main that touches wiki/, or locally
with --push.

What the GitHub wiki cannot take as-is, and what this does about it:

- Its page namespace is flat. `clients/ios.md` becomes the page `ios`. The
  tree has no duplicate basenames today; the script refuses to publish if
  that stops being true rather than letting one page silently overwrite
  another.
- YAML frontmatter renders as a table at the top of a page. It is stripped;
  the H1 in the body already carries the title.
- Links are relative paths with .md. They are rewritten to bare page names,
  anchors kept. A link to a file that is not published (wiki/raw/, tasks/,
  anything outside the published set) becomes a link to that file on main.
- `_index.md` is the landing page, so it becomes Home, and `_Sidebar.md` is
  generated from its section headings and links, which are the reading order.

wiki/raw/ is excluded on purpose: those are working notes and unprocessed
sources, not articles, and the authoring rule already says canonical pages
should not link into it.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = "XXJones21/Hearth"
WIKI_REMOTE = f"https://github.com/{REPO}.wiki.git"
BLOB = f"https://github.com/{REPO}/blob/main/"
EXCLUDE_DIRS = {"raw"}
RENAMES = {"_index.md": "Home.md"}

ROOT = Path(__file__).resolve().parent.parent
WIKI = ROOT / "wiki"

FRONTMATTER = re.compile(r"\A---\r?\n.*?\r?\n---\r?\n", re.DOTALL)
LINK = re.compile(r"(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)")
IMAGE = re.compile(r"\!\[([^\]]*)\]\(([^)\s]+)\)")


def collect() -> dict[Path, str]:
    """Map each published source file to its page filename."""
    pages: dict[Path, str] = {}
    seen: dict[str, Path] = {}
    for src in sorted(WIKI.rglob("*.md")):
        rel = src.relative_to(WIKI)
        if rel.parts[0] in EXCLUDE_DIRS:
            continue
        name = RENAMES.get(rel.name, rel.name)
        if name in seen:
            sys.exit(f"page name collision: {rel} and {seen[name].relative_to(WIKI)} both become {name}")
        seen[name] = src
        pages[src] = name
    return pages


def rewrite_target(target: str, src: Path, pages: dict[Path, str]) -> str:
    if re.match(r"^[a-z]+:", target) or target.startswith("#"):
        return target
    path, _, anchor = target.partition("#")
    resolved = (src.parent / path).resolve()
    if resolved in pages:
        page = pages[resolved][:-3]
        return f"{page}#{anchor}" if anchor else page
    try:
        rel = resolved.relative_to(ROOT)
    except ValueError:
        return target
    url = BLOB + rel.as_posix()
    return f"{url}#{anchor}" if anchor else url


def render(src: Path, pages: dict[Path, str]) -> str:
    text = src.read_text(encoding="utf-8")
    text = FRONTMATTER.sub("", text, count=1)

    def link(m: re.Match) -> str:
        return f"[{m.group(1)}]({rewrite_target(m.group(2), src, pages)})"

    def image(m: re.Match) -> str:
        target = m.group(2)
        if re.match(r"^[a-z]+:", target):
            return m.group(0)
        resolved = (src.parent / target).resolve()
        try:
            rel = resolved.relative_to(ROOT).as_posix()
        except ValueError:
            return m.group(0)
        return f"![{m.group(1)}](https://raw.githubusercontent.com/{REPO}/main/{rel})"

    text = IMAGE.sub(image, text)
    text = LINK.sub(link, text)
    return text.lstrip("\r\n")


def sidebar(pages: dict[Path, str]) -> str:
    """The landing page's headings and links, as the wiki's left rail.

    Built from _index.md, which is the reading order. It used to be built from
    sitemap.md, a second index that drifted three pages out of date before it
    was retired; one source cannot disagree with itself.
    """
    src = WIKI / "_index.md"
    text = FRONTMATTER.sub("", src.read_text(encoding="utf-8"), count=1)
    sections: list[tuple[str, list[str]]] = []
    for line in text.splitlines():
        if line.startswith("## "):
            sections.append((line[3:].strip(), []))
        elif sections and line.lstrip().startswith("- [") and "](" in line:
            m = LINK.search(line)
            if m:
                sections[-1][1].append(f"- [{m.group(1)}]({rewrite_target(m.group(2), src, pages)})")
    out = ["**[Home](Home)**"]
    for title, links in sections:
        if not links:
            continue  # prose-only sections of the sitemap have no rail entry
        out += ["", f"**{title}**", ""] + links
    out += ["", "[What is not here](whats-not-here)"]
    return "\n".join(out) + "\n"


def build(out: Path) -> dict[Path, str]:
    pages = collect()
    for stale in out.glob("*.md"):
        stale.unlink()
    for src, name in pages.items():
        (out / name).write_text(render(src, pages), encoding="utf-8", newline="\n")
    (out / "_Sidebar.md").write_text(sidebar(pages), encoding="utf-8", newline="\n")
    return pages


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, help="render into this directory instead of a fresh wiki clone")
    ap.add_argument("--push", action="store_true", help="commit and push the rendered wiki to Hearth.wiki.git")
    ap.add_argument("--remote", default=WIKI_REMOTE)
    args = ap.parse_args()

    source_rev = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()

    if args.out and not args.push:
        args.out.mkdir(parents=True, exist_ok=True)
        pages = build(args.out)
        print(f"rendered {len(pages)} pages + _Sidebar into {args.out}")
        return

    work = ROOT / ".wiki-publish"
    if work.exists():
        shutil.rmtree(work)
    subprocess.run(["git", "clone", "--quiet", "--depth", "1", args.remote, str(work)], check=True)
    pages = build(work)
    subprocess.run(["git", "add", "-A"], cwd=work, check=True)
    changed = subprocess.run(["git", "status", "--porcelain"], cwd=work, capture_output=True, text=True).stdout.strip()
    if not changed:
        print(f"wiki already matches {source_rev}; nothing to publish")
        shutil.rmtree(work, ignore_errors=True)
        return
    msg = f"Publish wiki from {REPO}@{source_rev}"
    subprocess.run(["git", "-c", "user.name=publish-wiki", "-c", "user.email=publish-wiki@users.noreply.github.com", "commit", "-q", "-m", msg], cwd=work, check=True)
    if args.push:
        subprocess.run(["git", "push", "-q", "origin", "HEAD:master"], cwd=work, check=True)
        print(f"published {len(pages)} pages + _Sidebar as '{msg}'")
    else:
        print(f"rendered {len(pages)} pages into {work}; rerun with --push to publish")
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
