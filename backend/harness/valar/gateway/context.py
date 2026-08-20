"""Context assembly with a SANE, bounded, observable budget.

This is the explicit replacement for the banned band-aids:
  * NO 4-turn / 120-char history truncation — history is bounded by a generous
    token budget (config) and a generous max-turns safety cap, newest-first.
  * NO 6000-char persona cap — the persona prompt is bounded only by a generous
    persona token budget.
  * NO fixed 16k-ctx assumption — total budget is config (default 32k, room to
    grow toward the 200k MoE ceiling), logged as context-fill every turn.

Token counting is a dependency-free heuristic (chars / chars_per_token). It is
intentionally approximate; the telemetry records the estimate so the budget can
be tuned against the real backend's reported usage over time.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from ..brain import ChatMessage
from ..brain.prompt_dialect import PromptDialect
from ..brain.prompt_format import RenderedPrompt, render_prompt
from ..config import ContextBudget
from ..telemetry import TurnTelemetry


@dataclass
class Turn:
    user: str
    assistant: str


def estimate_tokens(text: str, chars_per_token: float) -> int:
    if not text:
        return 0
    return max(1, int(len(text) / chars_per_token))


def _trim_to_token_budget(text: str, budget_tokens: int, chars_per_token: float) -> str:
    """Trim from the FRONT (keep the most recent / most relevant tail) to fit."""
    if not text:
        return text
    max_chars = int(budget_tokens * chars_per_token)
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def _render_device_context(dc: dict | None) -> str:
    """Render the ambient 'Current context' block from the client's device_context.

    Always includes the current local time so the brain never guesses it or needs a
    time tool; adds location + locale/units only when the client supplies them.
    Time uses the client's timezone when given, else the server's local clock.
    """
    dc = dc or {}
    tz = str(dc.get("timezone") or "").strip()
    now = None
    if tz:
        try:
            from zoneinfo import ZoneInfo

            now = datetime.now(ZoneInfo(tz))
        except Exception:  # noqa: BLE001 - unknown tz / missing tzdata -> server local
            now = None
    if now is None:
        now = datetime.now()

    # Portable 12-hour format (avoid %-I / %#I); strip a single leading zero.
    clock = now.strftime("%I:%M %p")
    if clock.startswith("0"):
        clock = clock[1:]
    day = str(now.day)  # drop leading zero portably (no %-d / %#d)
    when = now.strftime(f"%A, %B {day}, %Y") + f", {clock}"
    lines = ["Current date and time: " + when + (f" ({tz})" if tz else "")]

    loc = dc.get("location")
    if isinstance(loc, dict):
        place = ", ".join(
            p for p in (str(loc.get("city") or "").strip(), str(loc.get("region") or "").strip()) if p
        )
        if place:
            lines.append(f"Operator location: {place}.")

    locale = str(dc.get("locale") or "").strip()
    units = str(dc.get("units") or "").strip()
    meta = ", ".join(p for p in (locale, f"{units} units" if units else "") if p)
    if meta:
        lines.append(f"Locale: {meta}.")

    # Session continuity: what the previous (auto-ended) session was about, so a
    # fresh session opens with context instead of amnesia. Written by the auto
    # session-end persist; absent/stale notes render nothing.
    try:
        from ..memory.continuity import read_continuity, render_continuity_line

        continuity = render_continuity_line(read_continuity())
        if continuity:
            lines.append(continuity)
    except Exception:  # noqa: BLE001 - continuity is additive, never breaks a turn
        pass

    # Due reminders ride the same rail as the clock. The house has no channel
    # that can speak unprompted, so a reminder is delivered by being IN the
    # context of the next thing said, every turn, until it is dismissed.
    try:
        from ..memory.journal_sync import engram_root
        from ..memory.reminders import render_due_line

        root = engram_root()
        if root is not None:
            line = render_due_line(root)
            if line:
                lines.append(line)
    except Exception:  # noqa: BLE001 - reminders are additive, never break a turn
        pass

    return "# Current context\n" + "\n".join(lines)


def _render_tool_priming(specs: list | None) -> str:
    """Harness-level tool-awareness block.

    The tools are also declared to the model formally (llama-server renders them
    into Gemma's native function-call format via the chat template). THIS block is
    the behavioral nudge that gets a persona-following 8B to actually reach for a
    tool on conversational phrasing ("what's it like today") instead of answering
    from general knowledge. It lives in Valar so every client (Echo/iOS/Quest) gets
    identical tool behavior — no per-client logic.
    """
    if not specs:
        return ""
    lines = [
        "# Your tools",
        "You can call these tools. For anything real-time, factual, or specific to "
        "the operator (weather, news, web facts, things they asked you to remember), "
        "CALL the matching tool instead of answering from memory or guessing:",
    ]
    for name, desc in specs:
        short = str(desc or "").strip().split(". ")[0].strip().rstrip(".")
        lines.append(f"- {name}: {short}." if short else f"- {name}")
    lines.append(
        "When a tool needs a detail you already have, fill it from context -- e.g. "
        "for weather, use the operator's location from '# Current context' rather "
        "than asking them where they are. Only answer directly when no tool fits. "
        "When the topic changes, call the tool again with a NEW query -- do not "
        "reuse earlier tool results from the conversation. For questions about a "
        "specific day or period (yesterday, last week, this month), put the period "
        "in the memory query -- the journal is dated, and only dated records prove "
        "WHEN something happened; treat any undated or old-dated note as background, "
        "never as recent work. When a follow-up narrows the topic, search again "
        "with the refined words instead of answering from what you already found."
    )
    return "\n".join(lines)


class ContextAssembler:
    def __init__(self, budget: ContextBudget):
        self.budget = budget
        self.dialect = PromptDialect.OPENAI

    def set_dialect(self, dialect: PromptDialect) -> None:
        self.dialect = dialect or PromptDialect.OPENAI

    def render(
        self,
        messages: list,
        *,
        tools: list | None = None,
        enable_thinking: bool = False,
    ) -> RenderedPrompt:
        """Format the ChatMessage IR for the dialect set when the model loaded."""
        return render_prompt(
            messages,
            dialect=self.dialect,
            tools=tools,
            enable_thinking=enable_thinking,
        )

    def build(
        self,
        *,
        system_prompt: str,
        memory_block: str,
        history: list[Turn],
        user_text: str,
        telemetry: TurnTelemetry,
        device_context: dict | None = None,
        tool_specs: list | None = None,
    ) -> list[ChatMessage]:
        cpt = self.budget.chars_per_token

        # Persona system prompt — bounded by a generous token budget, not 6000 chars.
        persona = _trim_to_token_budget(
            system_prompt, self.budget.persona_token_budget, cpt
        )
        # Memory block — bounded by the memory budget.
        memory = _trim_to_token_budget(
            memory_block, self.budget.memory_token_budget, cpt
        )
        # Ambient "Current context" (the SCX block): current time always, plus
        # location/locale when the client supplies them. Always present so the
        # brain never guesses the time or needs a time tool.
        device_block = _render_device_context(device_context)
        tool_block = _render_tool_priming(tool_specs)

        # Compose the system message: persona, current context, tool awareness, memory.
        parts = [persona, device_block]
        if tool_block:
            parts.append(tool_block)
        if memory:
            parts.append(f"# Relevant memory (from Engram)\n{memory}")
        system_content = "\n\n".join(p for p in parts if p)

        # History: newest-first selection within the history token budget AND
        # the generous max-turns safety cap. NO 4-turn / 120-char limit.
        selected: list[Turn] = []
        used = 0
        turns_considered = history[-self.budget.max_history_turns :]
        for turn in reversed(turns_considered):
            t_tokens = estimate_tokens(turn.user, cpt) + estimate_tokens(turn.assistant, cpt)
            if used + t_tokens > self.budget.history_token_budget and selected:
                break
            selected.append(turn)
            used += t_tokens
        selected.reverse()

        messages: list[ChatMessage] = [ChatMessage("system", system_content)]
        for turn in selected:
            if turn.user:
                messages.append(ChatMessage("user", turn.user))
            if turn.assistant:
                messages.append(ChatMessage("assistant", turn.assistant))
        messages.append(ChatMessage("user", user_text))

        # Telemetry: record context-fill per section.
        telemetry.persona_tokens = estimate_tokens(persona, cpt)
        telemetry.memory_tokens = estimate_tokens(memory, cpt)
        telemetry.history_tokens = used
        telemetry.user_tokens = estimate_tokens(user_text, cpt)
        telemetry.history_turns_included = len(selected)
        telemetry.context_budget = self.budget.max_context_tokens
        telemetry.prompt_tokens_est = (
            telemetry.persona_tokens
            + telemetry.memory_tokens
            + telemetry.history_tokens
            + telemetry.user_tokens
        )
        return messages
