"""Web search / news tool -- keyless HTTP.

Uses the DuckDuckGo Instant Answer API (api.duckduckgo.com), which is free and
needs no key. It returns an abstract / definition / related topics for a query --
good for "what is X", "who is Y", quick facts, and headline-style lookups. It is
deliberately lightweight: a full SERP scraper or a paid search API
(Brave/SerpAPI/Tavily) is a follow-up, registered as another handler behind the
same registry with no loop change.

Standalone + keyless. Synchronous ``urllib`` (the registry runs it in a thread).
Failures degrade to ToolResult.error. ``web_search`` answers general queries;
``news_headlines`` is a thin wrapper that biases the query toward current events
(DDG Instant Answer is not a true news feed -- a dedicated news API is the proper
upgrade and is noted in the roadmap).
"""

from __future__ import annotations

import json
import logging
import urllib.parse
import urllib.request

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.web_search")

_DDG_URL = "https://api.duckduckgo.com/"
_TIMEOUT_S = 10
_MAX_TOPICS = 3
_CARD_BODY_CHARS = 280


def _clip(text: str, limit: int = _CARD_BODY_CHARS) -> str:
    """Word-boundary clip for idle-host card bodies (the spoken/model content
    stays full length; only the card teaser is shortened)."""
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(",;:")
    return cut + "..."


def _ddg(query: str) -> dict:
    params = {"q": query, "format": "json", "no_html": 1, "skip_disambig": 1, "t": "valar"}
    full = f"{_DDG_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(full, headers={"User-Agent": "Valar/1.0"})
    with urllib.request.urlopen(req, timeout=_TIMEOUT_S) as resp:  # noqa: S310
        return json.loads(resp.read().decode("utf-8"))


def _summarize(data: dict, query: str) -> ToolResult:
    abstract = (data.get("AbstractText") or data.get("Abstract") or "").strip()
    answer = (data.get("Answer") or "").strip()
    definition = (data.get("Definition") or "").strip()
    source = (data.get("AbstractSource") or data.get("DefinitionSource") or "").strip()

    if answer:
        return ToolResult(content=answer, data={"query": query, "kind": "answer"})
    if abstract:
        tail = f" (via {source})" if source else ""
        return ToolResult(content=abstract + tail, data={"query": query, "kind": "abstract"})
    if definition:
        tail = f" (via {source})" if source else ""
        return ToolResult(content=definition + tail, data={"query": query, "kind": "definition"})

    topics = []
    for t in data.get("RelatedTopics", []) or []:
        text = t.get("Text") if isinstance(t, dict) else None
        if text:
            topics.append(text.strip())
        if len(topics) >= _MAX_TOPICS:
            break
    if topics:
        return ToolResult(
            content="Here is what I found: " + " | ".join(topics),
            data={"query": query, "kind": "related", "topics": topics},
        )
    return ToolResult(
        content=f"I could not find a quick answer for '{query}'.",
        ok=False,
        data={"query": query, "kind": "none"},
    )


def web_search(args: dict) -> ToolResult:
    """args: {query: str}. Returns a quick instant-answer summary for the query."""
    query = str(args.get("query") or "").strip()
    if not query:
        return ToolResult.error("web search needs a query.")
    try:
        data = _ddg(query)
    except Exception as exc:  # noqa: BLE001
        logger.warning("web search failed for %r: %s", query, exc)
        return ToolResult.error("I could not reach the web just now.")
    return _summarize(data, query)


def news_headlines(args: dict) -> ToolResult:
    """args: {topic?: str}. Best-effort current-events lookup. DDG Instant Answer
    is not a true news feed -- a dedicated news API (e.g. NewsAPI/GDELT) is the
    proper upgrade; this gives a reasonable summary today."""
    topic = str(args.get("topic") or "").strip()
    query = f"latest news {topic}".strip() if topic else "today's top news"
    try:
        data = _ddg(query)
    except Exception as exc:  # noqa: BLE001
        logger.warning("news lookup failed for %r: %s", topic, exc)
        return ToolResult.error("I could not reach the news just now.")
    result = _summarize(data, query)
    if result.ok:
        # UI card (Generative UI Phase A): a brief_text teaser for the idle host.
        title = f"Headlines: {topic}" if topic else "Headlines"
        result.data["ui_component"] = {
            "version": 1,
            "type": "brief_text",
            "props": {"title": title, "body": _clip(result.content)},
        }
    return result
