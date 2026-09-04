#!/usr/bin/env python3
"""Find where the wiki says the same thing twice, and where it plans to.

The linter checks a page against the conventions. This checks pages against
each other: which sections duplicate which, what is unique and would be lost
if a page were retired, and where the corpus has written down an intention to
create a page that already exists in substance.

It reports. It does not decide.

That distinction is the whole design. Similarity cannot tell duplication from
parallel structure: `clients/android.md` and `clients/ios.md` are the highest
scoring pair in this corpus, and both are correct, because they share the
platform overview spine while describing different platforms. Meanwhile
`install-macos.md` and `installing.md` score slightly lower and one of them
should not exist. Only the learning objectives separate those two cases, so a
`delete` verdict belongs to the researcher reading this output, never to the
arithmetic in here.

Clustering runs on sections rather than whole documents. Connected components
over whole-document similarity chained nine unrelated pages together through
intermediaries, which is transitive drift and not a nine-way duplication.

Run it from the repository root:

    python scripts/doc_graph.py            # the report
    python scripts/doc_graph.py --json     # the same, for the researcher
    python scripts/doc_graph.py --pairs    # whole-document pairs as context
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIKI = ROOT / "wiki"
RAW = WIKI / "raw"

# Section-level scores. A pair at or above DUPLICATE says the same thing; a
# pair above OVERLAP shares ground and is worth a human look.
DUPLICATE = 0.45
OVERLAP = 0.30
# Whole-document context only. Never used to cluster: see the docstring.
DOC_PAIR = 0.50

STOP = set("""a an the and or but if then than that this these those of to in on at by for with
from as is are was were be been being it its you your they their there here we our us i so not
no can could will would should may might must do does did done have has had one two what when
where which who whom how why all any both each few more most other some such only own same too
very just now also into out up down over under again further once about page hearth""".split())

# Prose that announces a page nobody has written. Cross-referenced against the
# clusters, this is the check that would have caught the install duplication
# before it grew: three pages announced a Windows install guide in writing, to
# mirror a page that was already duplicate, and nothing was watching.
PLANNED_EXEMPT = {"whats-not-here.md", "style-guide.md"}
PLANNED = re.compile(
    r"(does not exist yet|do not exist yet|mirroring \[|until that guide is written"
    r"|is not written yet|are not written yet|not built yet|has yet to be written)",
    re.I,
)


def tokens(text: str) -> list[str]:
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    words = re.findall(r"[a-z][a-z0-9'-]+", text.lower())
    return [w for w in words if w not in STOP and len(w) > 2]


def body(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if text.startswith("---"):
        end = text.find("\n---\n", 3)
        if end != -1:
            return text[end + 5:]
    return text


def sections(path: Path) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    heading: str | None = None
    buf: list[str] = []
    for line in body(path).splitlines():
        if line.startswith("## "):
            if heading is not None:
                out.append((heading, " ".join(buf)))
            heading, buf = line[3:].strip(), []
        elif heading is not None:
            buf.append(line)
    if heading is not None:
        out.append((heading, " ".join(buf)))
    return out


def cosine(a: list[str], b: list[str]) -> float:
    ca, cb = Counter(a), Counter(b)
    num = sum(ca[k] * cb[k] for k in set(ca) & set(cb))
    da = math.sqrt(sum(v * v for v in ca.values()))
    db = math.sqrt(sum(v * v for v in cb.values()))
    return num / (da * db) if da and db else 0.0


def pages() -> list[Path]:
    return sorted(
        p for p in WIKI.rglob("*.md")
        if RAW not in p.parents and p.name != "_index.md"
    )


def analyze() -> dict:
    files = pages()
    name = {p: p.relative_to(WIKI).as_posix() for p in files}
    docs = {p: tokens(body(p)) for p in files}

    # Whole-document pairs, reported as context and never used to cluster.
    pairs = []
    for i, a in enumerate(files):
        for b in files[i + 1:]:
            s = cosine(docs[a], docs[b])
            if s >= DOC_PAIR:
                pairs.append({"a": name[a], "b": name[b], "similarity": round(s, 2)})
    pairs.sort(key=lambda d: -d["similarity"])

    # Section-level best match on another page.
    index = [(p, h, tokens(t)) for p in files for h, t in sections(p)]
    matches, unique = [], defaultdict(list)
    edges = defaultdict(float)
    for p, h, tk in index:
        if not tk:
            continue
        best, where = 0.0, None
        for q, h2, tk2 in index:
            if q == p:
                continue
            s = cosine(tk, tk2)
            if s > best:
                best, where = s, (q, h2)
        if where and best >= OVERLAP:
            matches.append({
                "page": name[p], "section": h,
                "matches_page": name[where[0]], "matches_section": where[1],
                "similarity": round(best, 2),
                "verdict": "duplicate" if best >= DUPLICATE else "overlap",
            })
            if best >= DUPLICATE:
                edges[tuple(sorted((name[p], name[where[0]])))] += 1
        if best < DUPLICATE:
            unique[name[p]].append(h)

    # Cluster on shared duplicated sections, not on document chaining.
    adj = defaultdict(set)
    for (a, b), count in edges.items():
        if count >= 2:
            adj[a].add(b)
            adj[b].add(a)
    seen, clusters = set(), []
    for n in sorted(adj):
        if n in seen:
            continue
        stack, comp = [n], []
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            comp.append(cur)
            stack.extend(adj[cur] - seen)
        clusters.append(sorted(comp))

    planned = []
    for p in files:
        if name[p] in PLANNED_EXEMPT:
            continue
        for i, line in enumerate(body(p).splitlines(), 1):
            if PLANNED.search(line):
                planned.append({
                    "page": name[p], "line": i, "text": line.strip()[:110],
                })

    return {
        "document_pairs": pairs,
        "clusters": [
            {
                "pages": c,
                "shared_duplicate_sections": sum(
                    n for (a, b), n in edges.items() if a in c and b in c
                ),
            }
            for c in sorted(clusters, key=len, reverse=True)
        ],
        "sections": sorted(matches, key=lambda d: -d["similarity"]),
        "unique": {k: v for k, v in sorted(unique.items())},
        "planned": planned,
    }


def report(data: dict) -> None:
    print("CLUSTERS: pages sharing two or more duplicated sections")
    if not data["clusters"]:
        print("  none")
    for c in data["clusters"]:
        print(f"  [{len(c['pages'])} pages, {c['shared_duplicate_sections']} shared sections]")
        for p in c["pages"]:
            print(f"      {p}")
    print()

    dupes = [s for s in data["sections"] if s["verdict"] == "duplicate"]
    print(f"DUPLICATED SECTIONS ({len(dupes)})")
    for s in dupes:
        print(f"  {s['similarity']:.2f}  {s['page']} > {s['section']}")
        print(f"        == {s['matches_page']} > {s['matches_section']}")
    print()

    print("PLANNED DUPLICATION: prose announcing a page that may already exist")
    if not data["planned"]:
        print("  none")
    for e in data["planned"]:
        print(f"  {e['page']}:{e['line']}  {e['text']}")
    print()

    print("SALVAGE: sections not duplicated elsewhere, per page in a cluster")
    print("Nothing in a cluster is retired before these land somewhere.")
    inside = {p for c in data["clusters"] for p in c["pages"]}
    for page in sorted(inside):
        u = data["unique"].get(page, [])
        print(f"  {page}: {', '.join(u) if u else '(nothing unique)'}")
    print()
    print("This report does not recommend deleting anything. Two pages can be")
    print("near-identical and both correct: see the docstring.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--pairs", action="store_true", help="whole-document pairs too")
    args = ap.parse_args()

    if not WIKI.is_dir():
        print(f"no wiki directory at {WIKI}", file=sys.stderr)
        return 2

    data = analyze()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0
    report(data)
    if args.pairs:
        print()
        print("WHOLE-DOCUMENT PAIRS (context only, never used to cluster)")
        for d in data["document_pairs"]:
            print(f"  {d['similarity']:.2f}  {d['a']}  <->  {d['b']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
