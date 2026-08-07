"""
Engram Writer -- safe file operations for the Engram knowledge base.

Provides path-validated writes to Engram markdown files. All paths
must resolve under HEARTH_ENGRAM with no traversal allowed.
"""

import logging
import os
import re
from pathlib import Path

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


def _get_engram_root() -> Path:
    """Return the Engram root, raising if it is unconfigured or absent.
    A writer that cannot find its tree must say so; it must not choose one."""
    root = engram_root()
    if not root.is_dir():
        raise FileNotFoundError(f"HEARTH_ENGRAM points at no directory: {root}")
    return root


def _validate_engram_path(target: str) -> Path:
    """
    Validate and resolve a relative path within Engram.

    Raises ValueError for traversal attempts, non-markdown targets,
    or paths outside the Engram root.
    """
    root = _get_engram_root()

    if ".." in target:
        raise ValueError(f"Path traversal not allowed: {target}")

    if not target.endswith(".md"):
        raise ValueError(f"Only .md files can be written: {target}")

    # Resolve BOTH sides. resolve() follows junctions and symlinks, and on
    # Windows an Engram root reached through a junction resolves to a
    # different spelling than the configured one; comparing a resolved child
    # against an unresolved root rejected every write.
    resolved_root = root.resolve()
    resolved = (root / target).resolve()

    if resolved_root not in resolved.parents and resolved != resolved_root:
        raise ValueError(f"Path must resolve under Engram root: {target}")

    if not resolved.parent.exists():
        raise ValueError(f"Parent directory does not exist: {resolved.parent}")

    return resolved


def write_engram_file(target: str, content: str, mode: str = "append") -> dict:
    """
    Write content to an Engram markdown file.

    Args:
        target: Relative path within Engram (e.g. "Projects/valinor/claude.md")
        content: Markdown content to write
        mode: "overwrite" replaces the file, "append" adds to the end

    Returns:
        dict with operation result
    """
    resolved = _validate_engram_path(target)

    if mode == "overwrite":
        resolved.write_text(content, encoding="utf-8")
        logger.info(f"[ENGRAM_WRITER] Overwrote {target} ({len(content)} chars)")
    elif mode == "append":
        with open(resolved, "a", encoding="utf-8") as f:
            if not content.startswith("\n"):
                f.write("\n")
            f.write(content)
        logger.info(f"[ENGRAM_WRITER] Appended to {target} ({len(content)} chars)")
    else:
        raise ValueError(f"Invalid mode: {mode} (must be 'overwrite' or 'append')")

    return {
        "ok": True,
        "target": target,
        "resolved_path": str(resolved),
        "mode": mode,
        "chars_written": len(content),
    }


def append_under_heading(target: str, heading: str, content: str) -> dict:
    """
    Append content under a specific markdown heading in an Engram file.

    Finds the heading (## Heading) and appends content before the next
    heading of the same or higher level.
    """
    resolved = _validate_engram_path(target)

    if not resolved.exists():
        raise FileNotFoundError(f"File not found: {target}")

    existing = resolved.read_text(encoding="utf-8")
    heading_pattern = re.compile(
        rf"^(#{{1,6}})\s+{re.escape(heading)}\s*$", re.MULTILINE
    )
    match = heading_pattern.search(existing)

    if not match:
        return write_engram_file(target, f"\n## {heading}\n\n{content}\n", mode="append")

    heading_level = len(match.group(1))
    insert_pos = match.end()

    next_heading = re.compile(
        rf"^#{{{1},{heading_level}}}\s+", re.MULTILINE
    )
    next_match = next_heading.search(existing, insert_pos)

    if next_match:
        insertion_point = next_match.start()
    else:
        insertion_point = len(existing)

    updated = (
        existing[:insertion_point].rstrip()
        + "\n\n"
        + content.strip()
        + "\n\n"
        + existing[insertion_point:]
    )

    resolved.write_text(updated, encoding="utf-8")
    logger.info(f"[ENGRAM_WRITER] Inserted under '{heading}' in {target}")

    return {
        "ok": True,
        "target": target,
        "resolved_path": str(resolved),
        "mode": "insert_under_heading",
        "heading": heading,
        "chars_written": len(content),
    }


async def write_engram_task(task: dict, state: dict) -> dict:
    """
    Execute skill task handler for engram_write tasks.

    Called by load_skill.py's task dispatch loop for task["type"] == "engram_write".

    Task format:
      {
        "type": "engram_write",
        "id": "ENGRAM-1",
        "target": "Projects/valinor/claude.md",
        "section": "Current Status",
        "content": "Pipeline refactored to...",
        "mode": "append"
      }
    """
    target = task.get("target", "")
    content = task.get("content", "")
    mode = task.get("mode", "append")
    section = task.get("section")

    if not target:
        logger.warning("[ENGRAM_WRITER] Task missing 'target' field")
        return {"ok": False, "error": "missing_target"}

    if not content:
        logger.warning("[ENGRAM_WRITER] Task missing 'content' field")
        return {"ok": False, "error": "missing_content"}

    try:
        if section:
            result = append_under_heading(target, section, content)
        else:
            result = write_engram_file(target, content, mode)
        return result
    except (ValueError, FileNotFoundError) as e:
        logger.error(f"[ENGRAM_WRITER] Task failed: {e}")
        return {"ok": False, "error": str(e)}
    except Exception as e:
        logger.error(f"[ENGRAM_WRITER] Unexpected error: {e}")
        return {"ok": False, "error": f"unexpected: {e}"}
