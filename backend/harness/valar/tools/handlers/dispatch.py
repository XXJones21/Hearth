"""Hand a self-contained task to another agent, and get its answer back.

The generic version of what `consult_memory`, `consult_liara` and `wright`
each do for one fixed target. Those three are hardcoded pairings: ask Selene,
ask Liara, run Wright. This is the primitive underneath them, so an
orchestrating persona can dispatch work it decides on rather than work someone
wired in advance.

WHY IT MATTERS BEYOND CONVENIENCE. Measured 2026-08-28: no agent in this
harness has ever dispatched another agent. Every nesting path is PYTHON
dispatching from inside a tool handler. `wright.py` reads as agent to agent,
but it is the wright TOOL's Python that fans out its five beats; the persona
that called the tool never dispatches anything. Without this handler, a
multi-agent flow can only be authored by writing a new Python handler, which
is why Wright, Mentat and Liara are three bespoke orchestrators rather than
three instances of one thing.

MODEL OR PERSONA. `persona` runs another identity on the shared resident
model, which is a prompt and sampling swap costing no reload. `model` names a
.gguf instead, which the router treats as a real class change and swaps for,
so it is the seam for benching one model against another inside a live flow.
Naming both is an error rather than a precedence puzzle.

DEPTH. Recursion was previously prevented by force-denying `consult_memory`
and `wright` to every subagent, which is a blocklist of two known cycles
rather than a bound. A generic dispatcher makes that insufficient, so this
counts depth in a context variable and refuses past `MAX_DISPATCH_DEPTH`. The
counter rides `contextvars`, so a task spawned under `asyncio.gather` inherits
its parent's depth without threading a parameter through every call.
"""

from __future__ import annotations

import logging

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.dispatch")

# The orchestrator is depth 0. Its workers are depth 1. A worker's own workers
# are depth 2, which is where Fennec's Investigate fan-out sits. Past that,
# nothing in the design asks for it and a cycle is more likely than a plan.
MAX_DISPATCH_DEPTH = 3

_MAX_TASK_CHARS = 4_000


async def dispatch_subagent(args: dict) -> ToolResult:
    """args: {task: str, persona?: str, model?: str, max_rounds?: int}."""
    task = str((args or {}).get("task") or "").strip()
    persona = str((args or {}).get("persona") or "").strip()
    model = str((args or {}).get("model") or "").strip()

    if not task:
        return ToolResult.error(
            "dispatch_subagent needs a task. Describe the whole job in one "
            "message: the worker starts with no memory of this conversation.",
            reason="bad_input",
        )
    if len(task) > _MAX_TASK_CHARS:
        return ToolResult.error(
            f"task too long ({len(task)} chars; cap {_MAX_TASK_CHARS}). Send "
            "the worker a brief, not a document.",
            reason="bad_input",
        )
    if persona and model:
        return ToolResult.error(
            "Name a persona or a model, not both. A persona brings its own "
            "prompt, voice and tools; a model is only weights.",
            reason="bad_input",
        )
    if not persona and not model:
        return ToolResult.error(
            "dispatch_subagent needs either a persona or a model.",
            reason="bad_input",
        )

    from ...agents.subagent import (
        current_depth,
        dispatch_depth,
        run_persona_subagent,
        subagents_ready,
    )

    if not subagents_ready():
        return ToolResult.error(
            "No subagent runtime is configured, so nothing can be dispatched.",
            reason="unsupported",
        )

    depth = current_depth()
    if depth >= MAX_DISPATCH_DEPTH:
        # Not a failure of the task; a refusal to go deeper. Say which, so the
        # model does the work itself rather than retrying the dispatch.
        return ToolResult.error(
            f"Already {depth} agents deep, which is the limit. Do this part "
            "yourself rather than delegating it again.",
            reason="denied",
        )

    try:
        rounds = int((args or {}).get("max_rounds") or 0)
    except (TypeError, ValueError):
        rounds = 0

    label = persona or model
    logger.info("dispatch depth=%d -> %s: %s", depth, label, task[:80])

    with dispatch_depth():
        try:
            if persona:
                kw = {"max_rounds": rounds} if rounds > 0 else {}
                res = await run_persona_subagent(persona, task, **kw)
            else:
                kw = {"max_rounds": rounds} if rounds > 0 else {}
                res = await run_persona_subagent(
                    _model_persona_name(), task, model_path=model, **kw
                )
        except Exception as exc:  # noqa: BLE001 - a worker never kills the caller
            logger.warning("dispatch to %s raised: %s", label, exc)
            return ToolResult.error(
                f"The {label} worker failed: {exc}", reason="internal"
            )

    if not res.get("ok"):
        err = res.get("error") or "no answer"
        return ToolResult.error(
            f"The {label} worker could not finish: {err}", reason="internal"
        )

    body = (res.get("content") or "").strip()
    if not body:
        return ToolResult.error(
            f"The {label} worker returned nothing.", reason="internal"
        )

    return ToolResult(
        content=(
            f"{label} reports:\n{body}\n"
            "This is the worker's own answer. Use it or say what is still "
            "missing; do not present it as something you did yourself."
        ),
        data={
            "agent": label,
            "kind": "persona" if persona else "model",
            "tools_used": res.get("tools_used") or [],
            "depth": depth + 1,
        },
    )


def _model_persona_name() -> str:
    """Which identity carries a bare-model dispatch.

    A model has no prompt of its own, so it borrows the default persona's and
    overrides only the weights. Deliberately the default rather than the
    caller: a bench run should not inherit whoever happened to dispatch it.
    """
    from ...agents.subagent import default_persona_name

    return default_persona_name()
