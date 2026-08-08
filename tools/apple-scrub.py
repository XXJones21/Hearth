#!/usr/bin/env python3
"""Copy Valinor's Apple client into Hearth, applying the manifest's rewrites.

The migration plan's section B, as a script. It reads apple-client/manifest.yaml,
copies each crossing file to its destination, and applies the rename, port and
identifier tables. It is deterministic and re-runnable, which is what lets a
re-scrub fix a mistake instead of a hand edit compounding it.

Two properties carry the design:

  - Substitutions come from the MANIFEST, never from constants here. The app
    group appears in three files and the URL scheme in three places, and every
    disagreement between copies is silent -- the widget reads an empty container
    and draws its fallback orb, which is indistinguishable from a widget that is
    working and waiting.

  - It refuses to write over the `generated` layer. The project file, the
    entitlements and the xcconfigs are hand-made and must survive a re-scrub.
    That boundary is why `disposition` exists as a manifest column.

What it does NOT do, deliberately: the named subtractions. Removing the Mentat
poll from ChatViewModel or the four tool labels from HouseStatusBar is judgment,
not substitution, and a regex that tried would eventually eat something else.
Every `edits` file prints its manifest note after it is written, so the work is
in front of whoever runs this rather than in a document they have to remember.

Usage:
    tools/apple-scrub.py --area 1
    tools/apple-scrub.py --area 1 --check      # report, write nothing
    tools/apple-scrub.py                       # every area

Exit status is 0 when the scrub ran clean and 1 when a source was missing or a
gate found a literal that should not have survived.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "apple-client" / "manifest.yaml"

# Literals that must not survive into apple-client/. This is migration plan F1
# run per area rather than once at the end, because the whole point of an area
# gate is that it fires before the next area buries the evidence.
# Note what is NOT here: joshuajones. Migration plan F1 item 2 greps for it and
# would now fail by design -- the identifier family deliberately keeps that
# namespace, because the constraint that actually matters is not sharing an
# operating-system store with Valinor, and com.joshuajones.Hearth against
# com.joshuajones.Valinor collides on none of them. See implementation plan 2.4.
GATES = [
    ("valinor", re.compile(r"valinor", re.I)),
    ("RFC1918 literal", re.compile(r"\b10\.\d+\.\d+\.\d+\b|\b192\.168\.")),
    ("old port", re.compile(r":(8700|8765|8766|8080|8702)\b")),
    ("absolute path", re.compile(r"D:/Tools|/Users/jones/Valinor")),
]


def load_manifest(path: Path) -> dict:
    try:
        import yaml
    except ImportError:
        raise SystemExit("this needs pyyaml: pip install pyyaml") from None
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def build_substitutions(manifest: dict) -> list[tuple[re.Pattern, str, str]]:
    """The rewrite table, in the order it must be applied.

    Specific before general. The blanket Valinor -> Hearth pass runs last so
    that anything with its own rule -- a defaults key, a widget kind, the URL
    scheme -- has already been handled by that rule and is not caught twice.
    """
    renames = manifest.get("renames") or {}
    identity = manifest.get("identity") or {}
    subs: list[tuple[re.Pattern, str, str]] = []

    def add(pattern: str, replacement: str, label: str) -> None:
        subs.append((re.compile(pattern), replacement, label))

    # Type names. Word-boundary so ValinorState does not become HearthState via
    # the Valinor rule and then get renamed twice.
    for old, new in (renames.get("types") or {}).items():
        add(rf"\b{re.escape(old)}\b", new, f"type {old} -> {new}")

    # UserDefaults keys, quoted so a bare word in prose is not caught.
    for old, new in (renames.get("defaults_keys") or {}).items():
        if new == "DROP":
            continue
        add(rf'"{re.escape(old)}"', f'"{new}"', f"defaults key {old} -> {new}")

    # Widget kinds. Same quoting rule, and these are one-way after release.
    for old, new in (renames.get("widget_kinds") or {}).items():
        add(rf'kind:\s*"{re.escape(old)}"', f'kind: "{new}"', f"widget kind {old} -> {new}")

    # The URL scheme, in all three of its spellings.
    scheme = identity.get("url_scheme")
    if scheme:
        add(r"valinor://", f"{scheme}://", f"url scheme -> {scheme}")
        add(r'scheme == "valinor"', f'scheme == "{scheme}"', "url scheme guard")

    # Ports. Hearth's block is 18700 and the reason is written down: the
    # development machine runs Valinor on 8700, so a build defaulting to 8700
    # finds the personal house and adopts its memory, journal and personas.
    port = identity.get("default_port")
    if port:
        add(r"\b8700\b", str(port), f"port 8700 -> {port}")

    # Identifiers.
    add(r"group\.com\.joshuajones\.Valinor", identity.get("app_group", ""), "app group")
    add(r"com\.joshuajones\.Valinor\.ValinorWidgets", identity.get("bundle_id_widgets", ""), "widget bundle id")
    add(r"com\.joshuajones\.Valinor", identity.get("bundle_id_ios", ""), "app bundle id")

    # The blanket pass, last. Safe because every "valinor" string literal in the
    # source is either the URL scheme (renamed above) or a seeded journal
    # fixture (deleted by hand, not by this script) -- verified 2026-08-08. No
    # wire-protocol constant contains the word.
    add(r"\bValinor\b", "Hearth", "BLANKET Valinor -> Hearth")
    add(r"\bvalinor\b", "hearth", "BLANKET valinor -> hearth")
    return subs


def assert_no_hearth_rule(subs) -> None:
    """Migration plan B5, enforced rather than remembered.

    B5 says HearthPalette, HearthIcons, PersonaOrb and PersonaPalette must not
    be rewritten, because they are already correct and "a find-and-replace pass
    over the word Hearth would corrupt them". The danger is a rule that matches
    HEARTH -- not one that matches Valinor. Those four files still carry Valinor
    in their headers and their ValinorState references, and they need those
    renamed like everything else.

    So the protection is not "skip these files", which would leave the old brand
    in the one place the article calls already-branded. It is "no rule may match
    the word Hearth", checked here once against a probe string. Read as a
    file-skip it silently does the opposite of what B5 wants.
    """
    probe = "Hearth HearthPalette HearthState hearth.snapshot.v1"
    for pattern, replacement, label in subs:
        if pattern.search(probe):
            raise SystemExit(
                f"refusing to run: rule '{label}' matches an already-Hearth "
                f"string. See migration plan B5."
            )


def scrub(text: str, subs) -> tuple[str, list[str]]:
    applied: list[str] = []
    for pattern, replacement, label in subs:
        text, count = pattern.subn(replacement, text)
        if count:
            applied.append(f"{label} ({count})")
    return text, applied


_LINE_COMMENT = re.compile(r"//.*?$", re.M)
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def strip_comments(text: str) -> str:
    """Comments are prose, and the gates are about code.

    The gates exist to catch a coupling that survived the scrub: an identifier,
    an address, a port, a URL scheme, a user-facing string. They are not meant
    to catch a comment that says *why* the port is 18700 and not 8700, or that
    the parser below carries across from Valinor unchanged because it was paid
    for in bugs. That reasoning is the most valuable thing in the file and a
    gate that forced it out would be actively harmful -- the next person would
    rediscover the same bug for want of a sentence.

    Naive on purpose: a `//` inside a string literal takes the rest of that line
    with it. That direction is safe, because the gate is a search and losing a
    little text can only make it quieter about code it should have flagged --
    and every literal this hunts for (a bare host, a port, a scheme) is caught
    by its own pattern elsewhere in the line or in the F1 grep over the tree.
    """
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", text))


def gate(path: Path, text: str) -> list[str]:
    """Report WHERE and HOW OFTEN, not just that something survived.

    This used to return one line per file per pattern. During area 3 that made
    33 surviving `valinorState` references -- the property behind the whole
    state machine, missed because the blanket rule is word-anchored and only
    renamed the type -- look exactly like the single expected survivor sitting
    in a fixture that was about to be deleted anyway. A gate that fires without
    saying how loudly invites the reader to explain it away.
    """
    code = strip_comments(text)
    out = []
    for name, pattern in GATES:
        hits = pattern.findall(code)
        if not hits:
            continue
        lines = [
            i for i, line in enumerate(code.splitlines(), 1) if pattern.search(line)
        ]
        where = ", ".join(str(n) for n in lines[:5])
        if len(lines) > 5:
            where += f", +{len(lines) - 5} more"
        out.append(f"{path}: {name} x{len(hits)} (line {where})")
    return out


def work_items(manifest: dict, area: int | None):
    """(source, destination, disposition, note) for everything that crosses."""
    root = (manifest.get("source") or {}).get("root", "").rstrip("/")
    for component in manifest.get("components") or []:
        if area is not None and component.get("area") != area:
            continue
        if component.get("disposition") in ("generated", "excluded"):
            continue
        base_src = component.get("source")
        base_dst = component.get("destination")
        files = component.get("files")
        if files:
            for entry in files:
                disp = entry.get("disposition", component["disposition"])
                if disp in ("generated", "excluded") or not entry.get("to"):
                    continue
                yield (
                    f"{root}/{base_src.rstrip('/')}/{entry['from']}",
                    f"{base_dst.rstrip('/')}/{entry['to']}",
                    disp,
                    entry.get("note") or component.get("note"),
                )
        elif base_src:
            yield (
                f"{root}/{base_src.rstrip('/')}",
                base_dst,
                component["disposition"],
                component.get("note"),
            )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--manifest", default=str(MANIFEST))
    ap.add_argument("--area", type=int, help="only this area; omit for all")
    ap.add_argument("--check", action="store_true", help="report, write nothing")
    ap.add_argument("--valinor", help="override the manifest's source.path")
    args = ap.parse_args()

    manifest = load_manifest(Path(args.manifest))
    source_root = Path(args.valinor or (manifest.get("source") or {}).get("path"))
    dest_root = REPO / (manifest.get("destination") or {}).get("root", "apple-client/")
    subs = build_substitutions(manifest)
    assert_no_hearth_rule(subs)

    written, missing, failures, notes = 0, [], [], []
    for src_rel, dst_rel, disposition, note in work_items(manifest, args.area):
        src, dst = source_root / src_rel, dest_root / dst_rel
        if not src.exists():
            missing.append(src_rel)
            continue

        if src.is_dir():
            # Asset catalogs cross whole. Nothing inside them names Valinor.
            if not args.check:
                dst.mkdir(parents=True, exist_ok=True)
                shutil.copytree(src, dst, dirs_exist_ok=True)
            print(f"  dir      {dst_rel}")
            written += 1
            continue

        text = src.read_text(encoding="utf-8")
        if disposition == "verbatim":
            new_text, applied = text, []
        else:
            new_text, applied = scrub(text, subs)

        failures.extend(gate(Path(dst_rel), new_text))
        if note:
            notes.append((dst_rel, " ".join(note.split())))

        if not args.check:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(new_text, encoding="utf-8")
        print(f"  {disposition:9} {dst_rel}" + (f"   [{', '.join(applied)}]" if applied else ""))
        written += 1

    scope = f"area {args.area}" if args.area is not None else "all areas"
    print(f"\n{'would write' if args.check else 'wrote'} {written} paths ({scope})")

    if missing:
        print(f"\nMISSING SOURCES ({len(missing)}):")
        for m in missing:
            print(f"  {m}")
    if failures:
        print(f"\nGATE FAILURES ({len(failures)}) -- a literal survived the scrub:")
        for f in failures:
            print(f"  {f}")
    if notes:
        print(f"\nBY HAND ({len(notes)}) -- the scrub cannot make these edits:")
        for path, note in notes:
            print(f"  {path}\n      {note}")

    return 1 if (missing or failures) else 0


if __name__ == "__main__":
    sys.exit(main())
