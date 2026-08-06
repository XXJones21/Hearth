"""The persona-subagent primitive (2026-06-07).

WHY THIS EXISTS (the operator's framing -- this is why Valar is a harness and
not just persona/model hot-swapping on the brain): the brain serves tokens for
ONE resident model; identity lives in the harness. A subagent invocation gives
another persona a FRESH context window -- its own system prompt, its own
resolved tool registry, its own sampling -- against the same loaded model.
Sulivan invoking Selene is a prompt+sampling swap, not a model swap: no
reload, no VRAM, ~1-2s per pass.

The run is HEADLESS: the subagent's inner tool calls and results never reach
the caller's context window or the client. Only the final synthesized answer
returns. This is the same parallel-track shape as the TTS subagent and the UI
composer.

Reuses the existing machinery end to end:
  - ``PersonaEngine.load(name)``        the subagent's identity (cached)
  - ``resolve_registry(grants, caps)``  her tool subset (with a forced deny of
                                        ``consult_memory`` -- no nested
                                        consults in v1)
  - ``ToolCallingLoop``                 the bounded headless tool loop
  - ``brain.chat`` joined               the one-shot synthesis pass (the
                                        ``summarize_session`` pattern)

Runtime wiring: handlers are standalone (``handler(args) -> ToolResult``, no
brain/session access), so the gateway hands the shared seams to this module
once at startup via :func:`configure_subagents` -- the same process-singleton
idiom as ``EngramService``.
"""

from __future__ import annotations

import logging
from typing import Any

from ..brain import BrainStreamResult, ChatMessage, ChatOptions

logger = logging.getLogger("valar.agents.subagent")

# Bounded: a subagent answers in a few hops, it does not wander.
MAX_SUBAGENT_ROUNDS = 3

_TASK_FRAMING = (
    "You are being consulted as a subagent by another persona of the same "
    "assistant. Work the task below with your tools, then answer ONCE, "
    "concisely and factually. Your reply goes to the calling persona, not "
    "directly to the operator."
)

_runtime: dict[str, Any] = {}


def configure_subagents(brain: Any, personas: Any, config: Any) -> None:
    """Called once by the gateway at startup: gives subagent invocations the
    shared brain seam + persona engine + config without threading them through
    the standalone tool-handler contract."""
    _runtime["brain"] = brain
    _runtime["personas"] = personas
    _runtime["config"] = config
    logger.info("subagent runtime configured")


def subagents_ready() -> bool:
    return "brain" in _runtime


def _to_chat_messages(msgs: list[dict]) -> list[ChatMessage]:
    return [
        ChatMessage(
            role=d.get("role", "user"),
            content=d.get("content") or "",
            tool_calls=d.get("tool_calls"),
            tool_call_id=d.get("tool_call_id"),
            name=d.get("name"),
        )
        for d in msgs
    ]


async def run_persona_subagent(
    persona_name: str,
    task: str,
    max_rounds: int = MAX_SUBAGENT_ROUNDS,
) -> dict:
    """Run ``task`` as ``persona_name`` in a fresh context window.

    Returns ``{ok, content, tools_used, error?}``. Never raises -- a subagent
    failure degrades to ``ok: False`` and the calling handler decides what to
    tell the operator.
    """
    if not subagents_ready():
        return {"ok": False, "content": "", "tools_used": [],
                "error": "subagent runtime not configured"}
    brain = _runtime["brain"]
    personas = _runtime["personas"]
    config = _runtime["config"]

    try:
        persona = personas.load(persona_name)
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "content": "", "tools_used": [],
                "error": f"persona '{persona_name}' unavailable: {exc}"}

    # HER ChatOptions: the persona's deep_model sampling. Same model path as
    # the caller's persona (the daily 12B) = the router treats it as a no-op
    # class change; a different path would trigger a real swap, so keep
    # subagent personas on the shared daily model.
    dm = persona.config.get("deep_model") if isinstance(persona.config, dict) else None
    dm = dm if isinstance(dm, dict) else {}
    bc = config.brain
    opts = ChatOptions(
        max_tokens=int(dm.get("max_tokens", bc.max_tokens)),
        temperature=float(dm.get("temperature", bc.temperature)),
        top_p=float(dm.get("top_p", bc.top_p)),
        top_k=int(dm.get("top_k", bc.top_k)),
        model=bc.model,
        persona_name=persona.name,
        model_path=dm.get("path", ""),
    )

    # FRESH context window: her system prompt + the task. No caller history.
    msgs: list[dict] = [
        {"role": "system", "content": f"{persona.system_prompt}\n\n{_TASK_FRAMING}"},
        {"role": "user", "content": task},
    ]

    # Headless bounded tool loop with HER resolved registry. Two tools are
    # force-denied to every subagent regardless of persona grants: consult_memory
    # (no nested memory consults in v1) and wright (no nested pipeline -- the
    # Wright orchestrator runs AS a subagent inside the wright tool, so allowing it
    # to call the tool would recurse; the top-level persona drives the pipeline,
    # the subagent cannot re-enter it).
    tools_used: list[str] = []
    chat_tools = getattr(brain, "chat_tools", None)
    from ..tools import resolve_registry, tools_enabled
    from ..tools.loop import ToolCallingLoop

    if tools_enabled() and chat_tools is not None:
        cfg = persona.config if isinstance(persona.config, dict) else {}
        grants = cfg.get("tool_grants")
        grants = dict(grants) if isinstance(grants, dict) else {}
        grants["deny"] = list(grants.get("deny") or []) + ["consult_memory", "wright"]
        registry = resolve_registry(grants, None)
        if registry.names():

            async def brain_tool_call(m: list[dict], tools: list[dict]) -> dict:
                r = await chat_tools(_to_chat_messages(m), opts, tools)
                calls = (r or {}).get("tool_calls") or []
                for c in calls:
                    fn = c.get("function", {})
                    # Diagnosis visibility (2026-06-07): WHICH args (esp. the
                    # recall scope) the subagent chose decides answer quality.
                    logger.info(
                        "subagent %s calls %s(%s)",
                        persona_name, fn.get("name"), str(fn.get("arguments"))[:160],
                    )
                return {"content": (r or {}).get("content") or "", "tool_calls": calls}

            try:
                msgs = await ToolCallingLoop(registry).run(msgs, brain_tool_call)
                tools_used = [
                    d.get("name", "") for d in msgs if d.get("role") == "tool"
                ]
                tools_used = [t for t in tools_used if t]
            except Exception as exc:  # noqa: BLE001 - synthesis still runs
                logger.warning("subagent %s tool loop failed: %s", persona_name, exc)

    # The 12B sometimes emits nothing after consuming tool results (the known
    # template failure the voice loop also defends against). Two defenses:
    # an answer-now marker on the last tool message (template-safe, the
    # force-answer idiom), and a one-shot retry with an explicit user nudge.
    if tools_used:
        for d in reversed(msgs):
            if d.get("role") == "tool":
                d["content"] = (d.get("content") or "") + (
                    "\n\n[Tool work is complete. Write your final answer now "
                    "as instructed in the task. Do not call any more tools.]"
                )
                break

    async def _synthesize(messages: list[dict]) -> str:
        result = BrainStreamResult()
        chunks: list[str] = []
        async for delta in brain.chat(_to_chat_messages(messages), opts, result):
            chunks.append(delta)
        return "".join(chunks).strip()

    try:
        content = await _synthesize(msgs)
        if not content:
            logger.warning(
                "subagent %s synthesis empty — retrying with nudge", persona_name
            )
            content = await _synthesize(
                msgs
                + [{
                    "role": "user",
                    "content": (
                        "[Answer the original task now in plain language, using "
                        "the tool results above. Do not call tools or emit tool "
                        "syntax.]"
                    ),
                }]
            )
    except Exception as exc:  # noqa: BLE001
        logger.error("subagent %s synthesis failed: %s", persona_name, exc)
        return {"ok": False, "content": "", "tools_used": tools_used,
                "error": str(exc)}
    logger.info(
        "subagent %s done: tools=%s, %d chars: %r",
        persona_name, tools_used, len(content), content[:200],
    )
    return {"ok": bool(content), "content": content, "tools_used": tools_used}
