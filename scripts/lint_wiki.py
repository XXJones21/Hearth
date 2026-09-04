#!/usr/bin/env python3
"""Check the wiki against the conventions it publishes.

The rules are not invented here. Conventions 1 to 5 are the "Writing
documentation" block in wiki/developing.md, which every canonical article
already claims to follow:

  1. Markdown only. Relative links only. One H1 per article, matching the
     frontmatter title.
  2. Sentence case headings.
  3. Frontmatter carries title, status, type, last_reviewed, related, sources.
  4. Canonical articles never link to raw or unprocessed material.
  5. No em dashes. No emojis.

The style rules come from wiki/style-guide.md and the six shapes from
wiki/page-types.md. Anything mechanically checkable is checked here, so a
reviewer never spends a pass on something a regex can find.

Findings have two severities:

  error    Deterministic, no false positives. Fails the build.
  warning  Calibration signal. Reported, does not fail the build.

Run it from the repository root:

    python scripts/lint_wiki.py             # errors in full, warnings counted
    python scripts/lint_wiki.py --warnings  # warnings in full too
    python scripts/lint_wiki.py --summary   # counts per rule, no detail
    python scripts/lint_wiki.py --figures   # pending figure capture queue

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

REQUIRED_KEYS = ("title", "status", "type", "last_reviewed", "related", "sources")

# The six shapes in wiki/page-types.md.
TYPES = {
    "landing", "how-to", "concept",
    "decision-record", "reference", "platform-overview",
}

# The six values wiki/task-files.md defines. One vocabulary across wiki/ and
# tasks/, so moving between them needs no second set of habits. `draft` was
# the old placeholder and distinguished nothing: every page carried it.
STATUSES = {"open", "scoped", "design", "blocked", "decided", "closed"}

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
    "american", "british", "english",
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

# An absolute machine path in `sources`. PR #23 fixed eight of these by hand
# and nothing stopped them coming back. Matches a Windows drive letter and the
# WSL mount prefix, which are the two shapes this repository produced.
ABS_PATH = re.compile(r"^(?:[A-Za-z]:[/\\]|/mnt/[a-z]/)")

# American English. A tight list rather than a broad -ise/-our regex, because
# the broad form matches "supervised", "rising", and "promised".
BRITISH = re.compile(
    r"\b(summaris\w*|normalis\w*|organis\w*|recognis\w*|analys(?:e|ed|es|ing)|"
    r"catalogue[sd]?|behaviour\w*|colour\w*|licence[sd]?|defence|"
    r"labell\w+|modelling|travelling|centre[sd]?)\b",
    re.I,
)

# The terminology table in wiki/style-guide.md: the local server is the house.
GATEWAY = re.compile(r"\bthe gateway\b", re.I)

# The reader is "you". Engineering records under backend/ may name a third
# party as an actor, because the reader there is not the person acting.
READER_DRIFT = re.compile(r"\bthe (operator|user)s?\b", re.I)

# A bolded term opening a prose paragraph. A bold label alone on its line
# introducing a list (**Shape:**) is correct and common. The retired shape is a
# bolded term followed by a wall of prose: a list item that never became one.
# So the rule is keyed on the paragraph's length, not on the line.
BOLD_LEAD = re.compile(r"^\*\*[^*]+\*\*")
BOLD_LEAD_WORDS = 25

# The style guide has to quote the forms it bans. A page cannot both define
# the terminology rule and obey it.
QUOTES_BANNED_FORMS = {"style-guide.md"}

# A figure the author asked for and nobody has captured yet. The alt text is
# for the reader; the title, after the path, is the capture instruction.
PENDING_IMG = re.compile(
    r"!\[([^\]]*)\]\(([^)\s]*images/pending/[^)\s]*)(?:\s+\"([^\"]*)\")?\)"
)

SECTION_WORDS = 200
PARAGRAPH_WORDS = 60


class Finding:
    __slots__ = ("path", "line", "rule", "message", "severity")

    def __init__(
        self, path: Path, line: int, rule: str, message: str,
        severity: str = "error",
    ) -> None:
        self.path = path
        self.line = line
        self.rule = rule
        self.message = message
        self.severity = severity

    def __str__(self) -> str:
        rel = self.path.relative_to(WIKI.parent).as_posix()
        return f"{rel}:{self.line}: [{self.rule}] {self.message}"


def warn(path: Path, line: int, rule: str, message: str) -> Finding:
    return Finding(path, line, rule, message, "warning")


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


def frontmatter_list(lines: list[str], key: str) -> list[tuple[int, str]]:
    """The `- item` entries under a frontmatter key, as (line number, value).

    split_frontmatter only captures scalars, so a broken `related` entry was
    invisible to every check. That mattered once publish started rendering
    `related` as a See also section: an unresolvable entry stops being inert
    metadata and becomes a broken link a reader can click.
    """
    if not lines or lines[0].strip() != "---":
        return []
    out: list[tuple[int, str]] = []
    inside = False
    for i in range(1, len(lines)):
        text = lines[i]
        if text.strip() == "---":
            break
        if re.match(rf"^{key}:\s*$", text):
            inside = True
            continue
        if inside:
            m = re.match(r"^\s+-\s+(.*)$", text)
            if m:
                out.append((i + 1, m.group(1).strip()))
            elif text.strip():
                inside = False
    return out


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


def is_prose(text: str) -> bool:
    """True for a running-prose line: not a heading, list, table, or quote."""
    t = text.strip()
    if not t:
        return False
    return not re.match(r"^(#{1,6}\s|[-*+]\s|\d+\.\s|\||>|\[|!\[)", t)


def paragraphs(body: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """Prose paragraphs, as (first line number, joined text)."""
    out: list[tuple[int, str]] = []
    start: int | None = None
    buf: list[str] = []
    for n, text in body:
        if is_prose(text):
            if start is None:
                start = n
            buf.append(text.strip())
        elif buf:
            out.append((start or 0, " ".join(buf)))
            start, buf = None, []
    if buf:
        out.append((start or 0, " ".join(buf)))
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


def strip_code(text: str) -> str:
    """Inline code spans removed, so an identifier is never a prose finding."""
    return re.sub(r"`[^`]*`", " ", text)


def check(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    keys, start = split_frontmatter(lines)
    body = body_lines(lines, start)
    rel = path.relative_to(WIKI).as_posix()

    # Rule 3: frontmatter.
    if not keys:
        findings.append(Finding(path, 1, "frontmatter", "no frontmatter block"))
    for key in REQUIRED_KEYS:
        if key not in keys:
            findings.append(Finding(path, 1, "frontmatter", f"missing `{key}`"))

    # Rule 3: type and status carry a vocabulary, not free text.
    if "type" in keys and keys["type"] not in TYPES:
        findings.append(Finding(
            path, 1, "page-type",
            f'`{keys["type"]}` is not one of {", ".join(sorted(TYPES))}',
        ))
    if "status" in keys and keys["status"] not in STATUSES:
        findings.append(Finding(
            path, 1, "status-value",
            f'`{keys["status"]}` is not one of {", ".join(sorted(STATUSES))}',
        ))

    # `sources` records where a page came from. An absolute machine path is a
    # location nobody else can open.
    for n, value in frontmatter_list(lines, "sources"):
        if ABS_PATH.match(value):
            findings.append(Finding(path, n, "absolute-source", value))

    # `related` becomes the See also block at publish time, so every entry
    # has to resolve the way a body link does.
    for n, value in frontmatter_list(lines, "related"):
        if value.startswith(("http://", "https://")):
            continue
        if re.search(r"(^|/)raw/", value):
            findings.append(Finding(path, n, "raw-link", value))
            continue
        if not (path.parent / value.split("#")[0]).resolve().exists():
            findings.append(Finding(path, n, "dead-related", value))

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
        prose_text = strip_code(text)

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

        # Style guide: American English, and one name per concept.
        for m in BRITISH.finditer(prose_text):
            findings.append(Finding(path, n, "british-spelling", m.group(0)))
        if GATEWAY.search(prose_text) and rel not in QUOTES_BANNED_FORMS:
            findings.append(
                Finding(path, n, "terminology", "the gateway (use: the house)")
            )

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
            # A figure the author requested is a work order, not a dead link.
            # Failing the build on one would mean the author agent breaks CI
            # by doing its job well.
            if "images/pending/" in target:
                findings.append(warn(path, n, "figure-pending", target))
                continue
            resolved = (path.parent / target.split("#")[0]).resolve()
            if target.split("#")[0] and not resolved.exists():
                findings.append(Finding(path, n, "dead-link", target))

        # Style guide: the reader is "you". backend/ is the one exception.
        if not rel.startswith("backend/") and rel not in QUOTES_BANNED_FORMS:
            m = READER_DRIFT.search(prose_text)
            if m:
                findings.append(warn(path, n, "reader-drift", m.group(0)))

    # Style guide: keep paragraphs short, and write term lists as lists.
    for n, text in paragraphs(body):
        words = len(strip_code(text).split())
        if words > PARAGRAPH_WORDS:
            findings.append(warn(path, n, "long-paragraph", f"{words} words"))
        if BOLD_LEAD.match(text) and words > BOLD_LEAD_WORDS:
            findings.append(warn(path, n, "bold-lead", text.strip()[:70]))

    # Style guide: end a section before it sprawls.
    state = {"heading": None, "line": 0, "words": 0, "h3": False}

    def close_section() -> None:
        if state["heading"] and state["words"] > SECTION_WORDS and not state["h3"]:
            findings.append(warn(
                path, state["line"], "long-section",
                f'{state["words"]} words under "{state["heading"]}" with no H3',
            ))

    for n, text in body:
        if text.startswith("## "):
            close_section()
            state = {"heading": text[3:].strip(), "line": n, "words": 0, "h3": False}
        elif text.startswith("### "):
            state["h3"] = True
        elif state["heading"] and is_prose(text):
            state["words"] += len(strip_code(text).split())
    close_section()

    return findings


def figure_queue(pages: list[Path]) -> int:
    """Print every figure an author asked for and nobody has captured."""
    total = 0
    for page in pages:
        lines = page.read_text(encoding="utf-8").splitlines()
        rel = page.relative_to(WIKI.parent).as_posix()
        # Fence-aware, so the worked example in the style guide does not
        # become a phantom work order for a screenshot nobody wants.
        _, start = split_frontmatter(lines)
        for i, text in body_lines(lines, start):
            for alt, target, spec in PENDING_IMG.findall(text):
                total += 1
                print(f"{rel}:{i}")
                print(f"    path: {target}")
                print(f"    alt : {alt}")
                print(f"    spec: {spec or '(none given)'}")
                print()
    print(f"{total} figures pending capture")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--summary", action="store_true", help="counts only")
    ap.add_argument("--warnings", action="store_true", help="list warnings in full")
    ap.add_argument("--figures", action="store_true", help="pending figure queue")
    args = ap.parse_args()

    if not WIKI.is_dir():
        print(f"no wiki directory at {WIKI}", file=sys.stderr)
        return 2

    pages = sorted(
        p for p in WIKI.rglob("*.md")
        if RAW not in p.parents and p != RAW
    )

    if args.figures:
        return figure_queue(pages)

    findings: list[Finding] = []
    for page in pages:
        findings.extend(check(page))

    errors = [f for f in findings if f.severity == "error"]
    warnings = [f for f in findings if f.severity == "warning"]

    def counts(items: list[Finding]) -> dict[str, int]:
        out: dict[str, int] = {}
        for f in items:
            out[f.rule] = out.get(f.rule, 0) + 1
        return out

    if not args.summary:
        for f in errors:
            print(f)
        if errors:
            print()
        if args.warnings:
            for f in warnings:
                print(f"{f}  (warning)")
            if warnings:
                print()

    print(
        f"{len(pages)} pages checked, "
        f"{len(errors)} errors, {len(warnings)} warnings"
    )
    for rule, n in sorted(counts(errors).items(), key=lambda kv: -kv[1]):
        print(f"  {n:>4}  {rule}")
    if warnings:
        print("  warnings:")
        for rule, n in sorted(counts(warnings).items(), key=lambda kv: -kv[1]):
            print(f"  {n:>4}  {rule}")
        if not args.warnings and not args.summary:
            print("        run with --warnings to list them")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
