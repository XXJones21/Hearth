"""
Brain Sync -- Engram context loading and session persistence.

The memory layer's read and write side, shared by the harness gateway and its
memory tools:
  - load a project's or the global context for a turn
  - infer which project a question is about, from the project listing
  - write a session diary to Thoughts, past a three-turn threshold
  - keep the shared operator-facts file
"""

import logging
import os
import re
from datetime import datetime, timedelta
from pathlib import Path

from .engram_writer import append_under_heading

logger = logging.getLogger(__name__)

# The memory tree, and nothing but HEARTH_ENGRAM.
#
# What used to be here was a candidate list ending in one person's own
# Engram directory, with no environment variable able to point it anywhere
# else. That is the single most dangerous line in this migration: on a
# machine where the original install exists, a fresh Hearth would have found
# it, loaded someone else's memory, journal and personas, and looked like it
# was working. The candidate is deleted rather than demoted, because a
# fallback that silently finds the wrong brain is worse than a hard failure.
def engram_root() -> Path:
    """The memory root. Raises when unconfigured; never searches."""
    configured = (os.environ.get("HEARTH_ENGRAM") or "").strip()
    if not configured:
        raise FileNotFoundError(
            "HEARTH_ENGRAM is not set. Memory has no root and Hearth will not "
            "guess one. Point it at an empty directory for a fresh brain."
        )
    return Path(configured).expanduser()


ENGRAM_CONTEXT_MAX_CHARS = 4000
MIN_TURNS_FOR_SAVE = 3


def _get_engram_root() -> Path | None:
    """The root when it is configured and present, else None. Callers here
    all degrade to "no memory" rather than raising, which is right for a
    voice turn; the loud version is engram_root()."""
    try:
        root = engram_root()
    except FileNotFoundError as exc:
        logger.warning("[BRAIN_SYNC] %s", exc)
        return None
    return root if root.is_dir() else None


def _list_projects() -> list[str]:
    """Return list of available project directory names under Engram/Projects."""
    root = _get_engram_root()
    if not root:
        return []
    projects_dir = root / "Projects"
    if not projects_dir.exists():
        return []
    return [
        d.name for d in projects_dir.iterdir()
        if d.is_dir() and (d / "claude.md").exists()
    ]


def load_engram_context(project_name: str | None = None) -> str:
    """
    Read a project's claude.md from Engram and return it as context.

    Falls back to the global CLAUDE.md if no project is specified or found.
    Returns empty string if Engram is not available.
    """
    root = _get_engram_root()
    if not root:
        logger.warning("[BRAIN_SYNC] Engram root not found, skipping context load")
        return ""

    if project_name:
        project_path = root / "Projects" / project_name / "claude.md"
        if project_path.exists():
            content = project_path.read_text(encoding="utf-8")
            if len(content) > ENGRAM_CONTEXT_MAX_CHARS:
                content = content[:ENGRAM_CONTEXT_MAX_CHARS] + "\n\n[Truncated for prompt budget.]"
            logger.info(f"[BRAIN_SYNC] Loaded project context: {project_name} ({len(content)} chars)")
            return content

    global_path = root / "CLAUDE.md"
    if global_path.exists():
        content = global_path.read_text(encoding="utf-8")
        if len(content) > ENGRAM_CONTEXT_MAX_CHARS:
            content = content[:ENGRAM_CONTEXT_MAX_CHARS] + "\n\n[Truncated for prompt budget.]"
        logger.info(f"[BRAIN_SYNC] Loaded global Engram context ({len(content)} chars)")
        return content

    return ""


# ---------- Operator facts (shared cross-client memory via /remember) ----------
# A single global Engram file holds operator-stated facts so they stay consistent
# across every Valinor client (Telegram bot now; Apple/Quest/Desktop via the deep
# agent server) and are visible to Claude. The Telegram bot dual-writes here
# (Engram = source of truth) and mirrors to its local SQLite cache. Kept separate
# from load_engram_context so the 4000-char project-context cap never truncates
# facts (and vice versa).

OPERATOR_FACTS_TARGET = "operator-facts.md"
OPERATOR_FACTS_HEADING = "Facts"
OPERATOR_FACTS_MAX = 40


def _operator_facts_path() -> Path | None:
    root = _get_engram_root()
    return (root / OPERATOR_FACTS_TARGET) if root else None


def ensure_operator_facts_file() -> bool:
    """Create operator-facts.md with its heading if missing. Returns True when the
    file exists (or was created), False if Engram is unavailable."""
    path = _operator_facts_path()
    if path is None:
        return False
    if not path.exists():
        path.write_text(
            "# Operator Facts\n\n"
            "Shared facts about the operator, captured via `/remember` (Telegram) and "
            "other Valinor clients. Source of truth for cross-client memory.\n\n"
            f"## {OPERATOR_FACTS_HEADING}\n\n",
            encoding="utf-8",
        )
        logger.info("[BRAIN_SYNC] Created operator facts file: %s", path)
    return True


def add_operator_fact(text: str, source: str = "unknown") -> dict:
    """Append a fact under the Facts heading in the shared operator-facts file.
    Returns engram_writer's result dict, or {ok: False, error} if unavailable."""
    text = (text or "").strip()
    if not text:
        return {"ok": False, "error": "empty"}
    if len(text) > 1000:
        text = text[:1000].rstrip() + "..."
    if not ensure_operator_facts_file():
        return {"ok": False, "error": "engram_unavailable"}
    date = datetime.now().strftime("%Y-%m-%d")
    bullet = f"- [{date}] {text}  _(via {source})_"
    try:
        return append_under_heading(OPERATOR_FACTS_TARGET, OPERATOR_FACTS_HEADING, bullet)
    except (ValueError, FileNotFoundError) as e:
        logger.warning("[BRAIN_SYNC] add_operator_fact failed: %s", e)
        return {"ok": False, "error": str(e)}


def _read_operator_fact_lines() -> list[str]:
    """Return fact bullet bodies (oldest-first) from the operator-facts file."""
    path = _operator_facts_path()
    if path is None or not path.exists():
        return []
    facts: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("- "):
            facts.append(s[2:].strip())
    return facts


def load_operator_facts(limit: int = OPERATOR_FACTS_MAX) -> str:
    """Return the most recent operator facts as a system-prompt block, or '' if
    none. Small by design, so it can be injected every turn cheaply."""
    facts = _read_operator_fact_lines()
    if not facts:
        return ""
    recent = facts[-limit:]
    bulleted = "\n".join(f"- {f}" for f in recent)
    return (
        "Known facts about the operator (shared across all Valinor clients via /remember):\n"
        f"{bulleted}\n\n"
        "Prefer these stored facts over guessing; if asked about something a fact covers, use it."
    )


def search_operator_facts(query: str, limit: int = 20) -> list[str]:
    """Substring search across operator facts (terms >= 3 chars, case-insensitive),
    newest-first. Empty query returns the most recent facts."""
    facts = _read_operator_fact_lines()
    if not facts:
        return []
    terms = [t.lower() for t in re.findall(r"\w+", query or "") if len(t) >= 3]
    if not terms:
        return list(reversed(facts))[:limit]
    return [f for f in reversed(facts) if any(t in f.lower() for t in terms)][:limit]


# ---------- Recent-activity readers (for Selene/Liora consolidation) ----------
# No "list recent thoughts" reader existed; these scan Engram for what accrued in
# a time window so a scheduled reviewer can consolidate it. Parsing mirrors the
# format save_session_to_engram writes.

def _parse_thought(path: Path, slug: str, date_fallback: str) -> dict:
    """Parse a Thoughts/<slug>/claude.md entry into a dict."""
    text = path.read_text(encoding="utf-8")

    def field(label: str) -> str:
        m = re.search(rf"^- \*\*{re.escape(label)}:\*\*\s*(.+)$", text, re.MULTILINE)
        return m.group(1).strip() if m else ""

    title_m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    summary_m = re.search(
        r"^##\s+Summary\s*\n+(.+?)(?=\n##\s|\Z)", text, re.MULTILINE | re.DOTALL
    )
    return {
        "slug": slug,
        "date": field("Date") or date_fallback,
        "title": title_m.group(1).strip() if title_m else slug,
        "personality": field("Personality"),
        "project": field("Related Project"),
        "tags": field("Tags"),
        "summary": (summary_m.group(1).strip() if summary_m else "")[:500],
        "path": str(path),
    }


def list_recent_thoughts(days: int = 1) -> list[dict]:
    """Return Thoughts entries dated within the last `days` (today inclusive),
    newest-first. Empty list if Engram/Thoughts is unavailable."""
    root = _get_engram_root()
    if not root:
        return []
    thoughts_dir = root / "Thoughts"
    if not thoughts_dir.exists():
        return []
    cutoff = datetime.now().date() - timedelta(days=max(0, days - 1))
    out: list[dict] = []
    for entry in thoughts_dir.iterdir():
        if not entry.is_dir():
            continue
        m = re.match(r"^(\d{4}-\d{2}-\d{2})-", entry.name)
        if not m:
            continue
        try:
            entry_date = datetime.strptime(m.group(1), "%Y-%m-%d").date()
        except ValueError:
            continue
        if entry_date < cutoff:
            continue
        claude_path = entry / "claude.md"
        if claude_path.exists():
            out.append(_parse_thought(claude_path, entry.name, entry_date.isoformat()))
    out.sort(key=lambda t: t.get("date", ""), reverse=True)
    return out


def recent_project_activity(hours: int = 24) -> list[dict]:
    """Return project claude.md files modified within the last `hours`, newest-first.
    Each dict: {project, path, modified}. Empty list if Engram is unavailable."""
    root = _get_engram_root()
    if not root:
        return []
    projects_dir = root / "Projects"
    if not projects_dir.exists():
        return []
    cutoff = datetime.now().timestamp() - hours * 3600
    out: list[dict] = []
    for claude_path in projects_dir.rglob("claude.md"):
        try:
            mtime = claude_path.stat().st_mtime
        except OSError:
            continue
        if mtime < cutoff:
            continue
        rel = claude_path.relative_to(root)
        parent = rel.parent
        project = str(parent.relative_to("Projects")).replace("\\", "/") if parent != Path("Projects") else "(root)"
        out.append({
            "project": project,
            "path": str(rel).replace("\\", "/"),
            "modified": datetime.fromtimestamp(mtime).isoformat(timespec="seconds"),
        })
    out.sort(key=lambda p: p.get("modified", ""), reverse=True)
    return out


def infer_project_from_query(query: str, analyze_output: dict | None = None) -> str | None:
    """Map a query to a project directory under $HEARTH_ENGRAM/Projects.

    Derived, not tabulated. What was here was a hand-maintained table of one
    person's twenty-five project names and their nicknames, which is data rather
    than configuration and which a fresh install has none of. The directory
    listing is the registry now: a project is a project because it exists.
    """
    haystack = (query or "").lower()
    if analyze_output:
        plan = analyze_output.get("plan") or {}
        haystack = (
            f"{haystack} {analyze_output.get('intent', '')} "
            f"{plan.get('objective', '')}"
        ).lower()

    best: str | None = None
    best_len = 0
    for project in _list_projects():
        for spelling in {project.lower(), project.lower().replace("-", " ")}:
            # Longest match wins, so a two-word project name beats a one-word
            # one that happens to be a prefix of it.
            if len(spelling) >= 3 and spelling in haystack and len(spelling) > best_len:
                best, best_len = project, len(spelling)
    if best:
        logger.info(f"[BRAIN_SYNC] Inferred project '{best}' from the project listing")
    else:
        logger.debug("[BRAIN_SYNC] No project inferred from query")
    return best


async def save_session_to_engram(
    session_id: str,
    conversation_history: list[dict],
    persona_name: str | None = None,
    summary: dict | None = None,
) -> dict:
    """
    Save a session to Engram Thoughts.

    Uses the brain_sync skill (LLM) to extract a structured summary,
    then writes the thought entry and updates indexes. A caller that already
    holds a summary (e.g. Valar, whose brain seam talks to llama-server
    directly) passes it via ``summary`` to skip the extraction — this process
    must NOT fall into ModelManager.chat_completion's load_deep_llm path.

    Returns dict with save result metadata.
    """
    root = _get_engram_root()
    if not root:
        return {"saved": False, "reason": "engram_not_found"}

    user_turns = [m for m in conversation_history if m.get("role") == "user"]
    if len(user_turns) < MIN_TURNS_FOR_SAVE:
        logger.info(
            f"[BRAIN_SYNC] Skipping save: {len(user_turns)} user turns < {MIN_TURNS_FOR_SAVE} threshold"
        )
        return {"saved": False, "reason": "below_threshold", "user_turns": len(user_turns)}

    if summary is None:
        summary = await _extract_session_summary(conversation_history, persona_name)
    if not summary:
        return {"saved": False, "reason": "summary_extraction_failed"}

    slug = summary.get("title", "untitled")
    slug = re.sub(r"[^a-z0-9]+", "-", slug.lower()).strip("-")[:40]
    date_str = datetime.now().strftime("%Y-%m-%d")
    thought_dir_name = f"{date_str}-{slug}"
    thought_dir = root / "Thoughts" / thought_dir_name

    counter = 1
    while thought_dir.exists():
        thought_dir = root / "Thoughts" / f"{thought_dir_name}-{counter}"
        counter += 1

    thought_dir.mkdir(parents=True, exist_ok=True)

    personality = summary.get("personality", persona_name or "none")
    related_project = summary.get("related_project", "none")
    tags = ", ".join(summary.get("tags", []))
    decisions = "\n".join(f"- {d}" for d in summary.get("key_decisions", []))
    questions = "\n".join(f"- {q}" for q in summary.get("open_questions", []))
    actions = "\n".join(f"- [ ] {a}" for a in summary.get("action_items", []))

    claude_md = (
        f"# {summary.get('title', 'Untitled')}\n\n"
        f"- **Date:** {date_str}\n"
        f"- **Personality:** {personality}\n"
        f"- **Related Project:** {related_project}\n"
        f"- **Tags:** {tags}\n"
        f"- **Session ID:** {session_id}\n\n"
        f"## Summary\n\n{summary.get('summary', 'No summary available.')}\n\n"
        f"## Key Decisions\n\n{decisions or '- None recorded'}\n\n"
        f"## Open Questions\n\n{questions or '- None recorded'}\n\n"
        f"## Action Items\n\n{actions or '- None recorded'}\n"
    )

    (thought_dir / "claude.md").write_text(claude_md, encoding="utf-8")

    chatlog_lines = []
    for msg in conversation_history:
        role = msg.get("role", "unknown").capitalize()
        content = msg.get("content", "")
        timestamp = msg.get("timestamp", "")
        chatlog_lines.append(f"### {role} ({timestamp})\n\n{content}\n")

    chatlog_md = f"# Chat Log: {summary.get('title', 'Untitled')}\n\n" + "\n---\n\n".join(chatlog_lines)
    (thought_dir / "chatlog.md").write_text(chatlog_md, encoding="utf-8")

    _update_thoughts_index(
        root, thought_dir.name, date_str, personality, related_project,
        summary.get("summary", "")[:80],
    )

    logger.info(f"[BRAIN_SYNC] Session saved to Thoughts/{thought_dir.name}")
    return {
        "saved": True,
        "thought_slug": thought_dir.name,
        "thought_path": str(thought_dir),
        "personality": personality,
        "related_project": related_project,
    }


def _update_thoughts_index(
    root: Path, slug: str, date: str, personality: str, project: str, summary: str,
) -> None:
    """Append a row to Thoughts/_index.md and the relevant personality index."""
    row = f"| {date} | {slug} | {personality} | {project} | {summary} |"

    index_path = root / "Thoughts" / "_index.md"
    if index_path.exists():
        content = index_path.read_text(encoding="utf-8")
        table_end = content.rfind("|")
        if table_end != -1:
            next_newline = content.find("\n", table_end)
            if next_newline == -1:
                next_newline = len(content)
            updated = content[:next_newline + 1] + row + "\n" + content[next_newline + 1:]
            index_path.write_text(updated, encoding="utf-8")
            logger.debug(f"[BRAIN_SYNC] Updated Thoughts/_index.md")

    personality_lower = personality.lower().strip()
    personality_dir = root / "Thoughts" / personality_lower
    if personality_dir.exists():
        p_index = personality_dir / "_index.md"
        if p_index.exists():
            p_row = f"| {date} | {slug} | {project} | {summary} |"
            p_content = p_index.read_text(encoding="utf-8")
            p_table_end = p_content.rfind("|")
            if p_table_end != -1:
                p_next = p_content.find("\n", p_table_end)
                if p_next == -1:
                    p_next = len(p_content)
                p_updated = p_content[:p_next + 1] + p_row + "\n" + p_content[p_next + 1:]
                p_index.write_text(p_updated, encoding="utf-8")
                logger.debug(f"[BRAIN_SYNC] Updated Thoughts/{personality_lower}/_index.md")


async def _extract_session_summary(
    conversation_history: list[dict], persona_name: str | None,
) -> dict | None:
    """A structured summary of the session.

    The harness passes one in: its brain seam already holds the conversation and
    a live model. This path exists for callers that do not, and it produces the
    deterministic summary rather than reaching for the retired pipeline's model
    manager, which is not part of the product.
    """
    return _fallback_summary(conversation_history, persona_name)


def _fallback_summary(conversation_history: list[dict], persona_name: str | None) -> dict:
    """Basic summary extraction without LLM -- used when model is unavailable."""
    first_user_msg = ""
    for msg in conversation_history:
        if msg.get("role") == "user" and msg.get("content", "").strip():
            first_user_msg = msg["content"][:100]
            break

    title = re.sub(r"[^a-zA-Z0-9 ]+", "", first_user_msg)[:50] or "session"

    return {
        "title": title.strip(),
        "summary": f"Session with {len(conversation_history)} messages.",
        "personality": persona_name or "none",
        "related_project": "none",
        "key_decisions": [],
        "open_questions": [],
        "action_items": [],
        "tags": [],
    }


def update_project_context(project_name: str, updates: str) -> dict:
    """
    Append key decisions or status changes to a project's claude.md.
    """
    root = _get_engram_root()
    if not root:
        return {"ok": False, "error": "engram_not_found"}

    target = f"Projects/{project_name}/claude.md"
    try:
        return append_under_heading(target, "Key Decisions", updates)
    except Exception as e:
        logger.error(f"[BRAIN_SYNC] Failed to update project context: {e}")
        return {"ok": False, "error": str(e)}
