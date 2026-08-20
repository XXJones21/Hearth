"""Persona consults -- ask a housemate, as a subagent, and ground on the reply.

consult_memory (Selene) was the first caller of the persona-subagent
primitive (:mod:`valar.agents.subagent`); consult_liara (the CHOAM desk) is
its sibling. In both cases the question leaves the calling persona's context
entirely: the consulted persona gets a fresh context window, its own system
prompt and tool grants, runs a bounded headless tool loop, and returns one
compact synthesis. The caller grounds on 2-4 sentences; the detail rides a
generated_view card to the screen.

The consulted personas are DENIED the consult tools themselves (grants + a
forced deny in the primitive) -- no nested consults in v1.
"""

from __future__ import annotations

import logging

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.consult")

_SPOKEN_CHARS = 600
_SOURCES_CHARS = 200


async def consult_memory(args: dict) -> ToolResult:
    """args: {question: str}. Dispatch the question to the Selene subagent and
    return her synthesis (spoken summary + a generated_view card)."""
    question = str(args.get("question") or args.get("query") or "").strip()
    if not question:
        return ToolResult.error("what should I look up? Give me the question.")
    # The caller's model knows the question's intent best; default to
    # background (consult's niche IS personal history -- "Meta Quest" prose
    # legitimately contains the word "Meta", so personal-project notes MUST be
    # excluded from employer/history questions at the scope level, not by
    # ranking). 2026-06-07: the scope was renamed personal_projects -- the old
    # name "projects" collided with the WORD "projects" in employer questions
    # ("projects I worked on at Meta") and pulled the search into side-project
    # notes, which is exactly where "Meta Quest" lives.
    scope = str(args.get("scope") or "background").strip().lower()
    if scope == "projects":
        scope = "personal_projects"
    if scope not in ("background", "personal_projects", "sessions", "all"):
        scope = "background"
    logger.info("consult_memory: scope=%s question=%r", scope, question[:120])

    from ...agents import run_persona_subagent

    task = (
        "Research this question in the operator's Engram memory using your "
        f'tools. Call recall with scope="{scope}" and max_results=8 for every '
        "search you make. Remember: anything worked on AT an employer (Meta, "
        "Apple, Snap...) lives in scope=background; scope=personal_projects "
        "is ONLY their own side projects. Use project_status only if a "
        "specific project is named. Make a fresh, targeted recall per "
        "sub-topic.\n\n"
        f"Question: {question}\n\n"
        "Answer ONLY from what the tools return -- if the tool results do "
        "not answer the question, say so plainly instead of guessing. "
        "Results carry dates and ages; report them, and NEVER present an "
        "old-dated or undated note as recent activity. If the question is "
        "about a day or period, put that period in the recall query and "
        "answer only from records dated inside it. Reply "
        "with 2-4 short factual sentences -- EXCEPT when the question asks "
        "for a list or a number of items: then give exactly that list, one "
        "short line per item (this overrides your usual no-lists style; you "
        "are reporting to another persona, not speaking aloud). Then on a "
        "new line write SOURCES: followed by the note files you drew from, "
        "comma-separated."
    )
    res = await run_persona_subagent("Selene", task)
    if not res.get("ok"):
        logger.warning("Selene consult failed: %s", res.get("error"))
        return ToolResult.error(
            "my librarian could not reach the archives just now."
        )

    content = str(res.get("content") or "")
    spoken, _, sources = content.partition("SOURCES:")
    spoken = spoken.strip() or content.strip()
    sources = sources.strip()

    sections: list[dict] = [{"kind": "text", "body": spoken[:_SPOKEN_CHARS]}]
    if sources:
        sections.append({"kind": "divider"})
        sections.append({"kind": "text", "body": "Sources: " + sources[:_SOURCES_CHARS]})
    card = {
        "version": 1,
        "type": "generated_view",
        "props": {
            "template": "brief",
            "title": "From the archives",
            "sections": sections,
        },
    }
    return ToolResult(
        content=spoken,
        data={
            "ui_component": card,
            "consulted": "Selene",
            "tools_used": res.get("tools_used", []),
        },
    )


async def consult_liara(args: dict) -> ToolResult:
    """args: {question?: str}. Ask Liara, the CHOAM portfolio manager, for a
    portfolio/trading-day update. She reads the live wallet with her own tools
    and reports back; the caller never touches the wallet directly."""
    question = str(args.get("question") or "").strip() or (
        "Give the operator a daily status update on the CHOAM portfolio."
    )
    logger.info("consult_liara: question=%r", question[:120])

    from ...agents import run_persona_subagent

    task = (
        "The operator (relayed by Sulivan) is asking for a portfolio update. "
        "Call view_ledger FIRST -- it is the authoritative book; never answer "
        "from memory. Then answer the question from those numbers.\n\n"
        f"Question: {question}\n\n"
        "Reply with 2-4 short factual sentences covering NAV, deployed "
        "percentage, the notable positions or moves, and drawdown headroom "
        "-- plain numbers, no hedging. Then on a NEW final line write "
        "DATA: followed by one-line JSON with exactly these keys from the "
        'ledger: {"nav": number, "deployed_pct": number, "drawdown": number, '
        '"halt_limit": number, "positions": [{"ticker": str, "pct": number}]}. '
        "If the wallet tool fails, reply with EXACTLY the line "
        "'DESK-UNREACHABLE: <one plain sentence>' and nothing else; never "
        "invent numbers."
    )
    res = await run_persona_subagent("Liara", task)
    if not res.get("ok"):
        logger.warning("Liara consult failed: %s", res.get("error"))
        return ToolResult.error(
            "the trading desk is unreachable just now."
        )

    content = str(res.get("content") or "").strip()
    if not content:
        return ToolResult.error("the desk sent back an empty report.")
    # Wire-legible failure (2026-07-30): when Liara's own wallet call failed
    # she marks the reply; surface it as a TOOL ERROR (no card -- there is
    # nothing for the screen) so the voice loop's failed-turn instruction
    # fires and Sulivan never deflects to an empty card.
    if content.upper().startswith("DESK-UNREACHABLE"):
        detail = content.split(":", 1)[-1].strip() or "the desk is unreachable right now."
        return ToolResult.error(detail)

    # Structured tail: Liara appends "DATA: {json}". Split it off the spoken
    # report; if a BUILT workshop card is fed by this tool, emit that typed
    # card with the parsed data -- otherwise fall back to the generic brief.
    # This is the forge's use-side: the day a commissioned card finishes, the
    # same question starts rendering it, with zero further wiring.
    spoken, _, data_tail = content.partition("DATA:")
    spoken = spoken.strip() or content.strip()
    parsed: dict | None = None
    if data_tail.strip():
        try:
            import json as _json

            parsed = _json.loads(data_tail.strip())
        except ValueError:
            logger.info("Liara DATA tail unparseable; using generic card")

    card = None
    if parsed is not None:
        from .forge import find_card_for_source

        entry = find_card_for_source("consult_liara")
        if entry is not None:
            card = {
                "version": 1,
                "type": str(entry["type"]),
                "props": {"data": parsed},
            }
    if card is None:
        card = {
            "version": 1,
            "type": "generated_view",
            "props": {
                "template": "brief",
                "title": "From the trading desk",
                "sections": [{"kind": "text", "body": spoken[:_SPOKEN_CHARS]}],
            },
        }
    return ToolResult(
        content=spoken,
        data={
            "ui_component": card,
            "consulted": "Liara",
            "tools_used": res.get("tools_used", []),
        },
    )
