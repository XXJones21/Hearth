#!/usr/bin/env python3
"""Check the wiki against the conventions it publishes.

The rules are not invented here. They are the "Conventions" block in
wiki/_index.md, which every canonical article already claims to follow:

  1. Markdown only. Relative links only. One H1 per article, matching the
     frontmatter title.
  2. Sentence case headings.
  3. Frontmatter carries title, status, last_reviewed, related, sources.
  4. Canonical articles never link to raw or unprocessed material.
  5. No em dashes. No emojis.

Run it from the repository root:

    python scripts/lint_wiki.py            # check, exit 1 on any finding
    python scripts/lint_wiki.py --summary  # counts per rule, no detail

wiki/raw/ is source material and is not checked. The publish step strips it,
so nothing under it reaches a reader.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

WIKI = Path(__file__).resolve().parent.parent / "wiki"
RAW = WIKI / "raw"

REQUIRED_KEYS = ("title", "status", "last_reviewed", "related", "sources")

# Words that stay capitalized mid-heading because they are proper nouns.
PROPER = {
    "hearth", "valinor", "valar", "mentat", "selene", "sulivan",
    "windows", "macos", "ios", "visionos", "android", "linux", "apple",
    "vision", "pro", "quest", "github", "microsoft", "meta", "nvidia",
    "wsl", "wsl2", "gguf", "cuda", "metal", "opengl", "openxr", "mruk",
    "rust", "python", "swift", "swiftui", "kotlin", "typescript", "react",
    "tauri", "electron", "compose", "realitykit", "llama.cpp", "whisper",
    "neutts", "omnivoice.cpp", "diffusers", "sdxl", "mlx", "docker",
    "podman", "systemd", "lineageos", "echo", "show", "tailscale", "i",
    "mac", "xcode", "gradle", "npm", "cargo", "nsis", "testflight",
}

EMOJI = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF⬀-⯿️]"
)
EM_DASH = re.compile("—")
# " -- ", an em dash wearing a disguise. Anchored on whitespace rather than on
# word characters: an earlier version required a word char on the left and
# missed both a line that opens with the dashes and one where they follow
# `**bold**`. A `--flag` is not matched, because the trailing space is required.
EM_PROXY = re.compile(r"(?:(?<=\S)\s--\s|^\s*--\s)")
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
FENCE = re.compile(r"^\s*(```|~~~)")
# A raw/ document named in body prose. Naming one in `sources` is the
# convention working as designed; sending a reader to one is a dead end,
# because the publish step strips raw/ before the wiki ever sees it. Requires
# a .md so that a bare `raw/` (explaining the convention) and an unrelated
# path like /v1/raw/* do not trip it.
RAW_IN_PROSE = re.compile(r"(?<![\w/])(?:\.\./|wiki/)?raw/[\w./-]*\.md")


class Finding:
    __slots__ = ("path", "line", "rule", "message")

    def __init__(self, path: Path, line: int, rule: str, message: str) -> None:
        self.path = path
        self.line = line
        self.rule = rule
        self.message = message

    def __str__(self) -> str:
        rel = self.path.relative_to(WIKI.parent).as_posix()
        return f"{rel}:{self.line}: [{self.rule}] {self.message}"


def split_frontmatter(lines: list[str]) -> tuple[dict[str, str], int]:
    """Return the frontmatter keys and the line index where the body starts."""
    if not lines or lines[0].strip() != "---":
        return {}, 0
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            keys: dict[str, str] = {}
            for raw in lines[1:i]:
                m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", raw)
                if m:
                    keys[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            return keys, i + 1
    return {}, 0


def body_lines(lines: list[str], start: int) -> list[tuple[int, str]]:
    """Body lines outside fenced code blocks, as (1-based line number, text)."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for idx in range(start, len(lines)):
        text = lines[idx]
        if FENCE.match(text):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append((idx + 1, text))
    return out


def is_title_case(heading: str) -> bool:
    """True when a heading capitalizes words that are not proper nouns."""
    words = re.findall(r"[A-Za-z][\w.'-]*", heading)
    offenders = []
    for w in words[1:]:
        if not w[0].isupper() or w.isupper():
            continue
        # `Hearth.wsl` and `Hearth.app` are the proper noun plus an extension.
        if w.lower() in PROPER or w.lower().split(".")[0] in PROPER:
            continue
        offenders.append(w)
    return len(offenders) >= 1


def check(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    keys, start = split_frontmatter(lines)
    body = body_lines(lines, start)

    # Rule 3: frontmatter.
    if not keys:
        findings.append(Finding(path, 1, "frontmatter", "no frontmatter block"))
    for key in REQUIRED_KEYS:
        if key not in keys:
            findings.append(Finding(path, 1, "frontmatter", f"missing `{key}`"))

    # Rule 1: exactly one H1, matching the frontmatter title.
    h1s = [(n, t[2:].strip()) for n, t in body if t.startswith("# ")]
    if not h1s:
        findings.append(Finding(path, 1, "h1", "no H1"))
    elif len(h1s) > 1:
        findings.append(
            Finding(path, h1s[1][0], "h1", f"{len(h1s)} H1s, expected 1")
        )
    if h1s and "title" in keys and h1s[0][1] != keys["title"]:
        findings.append(
            Finding(
                path, h1s[0][0], "h1",
                f'H1 "{h1s[0][1]}" does not match frontmatter title "{keys["title"]}"',
            )
        )

    # Rule 2: sentence case headings.
    for n, text in body:
        m = re.match(r"^(#{1,6})\s+(.*)$", text)
        if m and is_title_case(m.group(2)):
            findings.append(
                Finding(path, n, "sentence-case", f'"{m.group(2)}"')
            )

    for n, text in body:
        # Rule 5: no em dashes, no emojis.
        if EM_DASH.search(text):
            findings.append(Finding(path, n, "em-dash", text.strip()[:70]))
        # A `--` filling a whole table cell is a placeholder, not punctuation.
        # Blank those cells before looking for em-dash proxies. The pipes are
        # matched by lookaround so adjacent empty cells both clear.
        prose = re.sub(r"(?<=\|)\s*--\s*(?=\|)", "  ", text)
        if EM_PROXY.search(prose):
            findings.append(Finding(path, n, "em-dash-proxy", text.strip()[:70]))
        if EMOJI.search(text):
            findings.append(Finding(path, n, "emoji", text.strip()[:70]))

        # Rule 4, the prose half: a reader cannot open anything under raw/.
        # A line already reported as a raw-link is not reported twice.
        linked_raw = any(
            re.search(r"(^|/)raw/", t.split()[0].strip("<>"))
            for t in MD_LINK.findall(text)
        )
        if not linked_raw:
            for ref in RAW_IN_PROSE.findall(text):
                findings.append(Finding(path, n, "raw-in-prose", ref))

        # Rules 1 and 4: relative links that resolve, and never into raw.
        for target in MD_LINK.findall(text):
            target = target.split()[0].strip("<>")
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            if re.search(r"(^|/)raw/", target):
                findings.append(Finding(path, n, "raw-link", target))
                continue
            resolved = (path.parent / target.split("#")[0]).resolve()
            if target.split("#")[0] and not resolved.exists():
                findings.append(Finding(path, n, "dead-link", target))

    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--summary", action="store_true", help="counts only")
    args = ap.parse_args()

    if not WIKI.is_dir():
        print(f"no wiki directory at {WIKI}", file=sys.stderr)
        return 2

    pages = sorted(
        p for p in WIKI.rglob("*.md")
        if RAW not in p.parents and p != RAW
    )
    findings: list[Finding] = []
    for page in pages:
        findings.extend(check(page))

    counts: dict[str, int] = {}
    for f in findings:
        counts[f.rule] = counts.get(f.rule, 0) + 1

    if not args.summary:
        for f in findings:
            print(f)
        if findings:
            print()

    print(f"{len(pages)} pages checked, {len(findings)} findings")
    for rule in sorted(counts, key=lambda r: -counts[r]):
        print(f"  {counts[rule]:>4}  {rule}")

    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
