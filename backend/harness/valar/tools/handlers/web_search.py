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
import re
import urllib.parse
import urllib.request

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.web_search")

_DDG_URL = "https://api.duckduckgo.com/"
_TIMEOUT_S = 10
_USER_AGENT = "Mozilla/5.0 (compatible; Hearth/1.0; +local)"
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


# --- reading a page, not just finding one ---------------------------------

_FETCH_MAX_CHARS = 12_000
_FETCH_HARD_MAX = 20_000
_FETCH_BYTES_CAP = 4_000_000


def _is_private_host(host: str) -> bool:
    """True for anything on this machine or this network.

    The house itself listens on loopback, as do its brain, its voice, and the
    operator's other software. A model that can be told "read this URL" can be
    told to read those, and a page it summarises out loud is a page it can be
    made to exfiltrate. Fetching is for the public web.
    """
    import ipaddress
    import socket

    host = (host or "").strip().lower().strip("[]")
    if not host or host in ("localhost", "localhost.localdomain"):
        return True
    if host.endswith(".local") or host.endswith(".internal"):
        return True
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return True  # cannot resolve: refuse rather than try
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if ip.is_loopback or ip.is_private or ip.is_link_local or ip.is_reserved:
            return True
    return False


def fetch_url(args: dict) -> ToolResult:
    """args: {url: str, max_chars?: int}. Read a public web page as text.

    web_search returns titles and snippets and nothing could open the result,
    so an answer that needed the page itself could only be assembled from
    fragments. This opens it.
    """
    url = str((args or {}).get("url") or "").strip().strip('"').strip("'")
    if not url:
        return ToolResult.error("fetch_url needs a URL.")
    if url.startswith("//"):
        url = "https:" + url
    if not re.match(r"^https?://", url, re.IGNORECASE):
        if "." in url.split("/")[0]:
            url = "https://" + url
        else:
            return ToolResult.error(
                f"{url!r} is not a web address. Only http and https can be read."
            )

    parsed = urllib.parse.urlparse(url)
    if _is_private_host(parsed.hostname or ""):
        return ToolResult.error(
            "That address is on this machine or this network, and fetching is "
            "for the public web only. Tell them plainly rather than trying "
            "another way in."
        )

    try:
        max_chars = int((args or {}).get("max_chars") or _FETCH_MAX_CHARS)
    except (TypeError, ValueError):
        max_chars = _FETCH_MAX_CHARS
    max_chars = max(500, min(max_chars, _FETCH_HARD_MAX))

    req = urllib.request.Request(
        url,
        headers={"User-Agent": _USER_AGENT, "Accept": "text/html,text/plain,*/*"},
    )
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT_S) as resp:  # noqa: S310
            ctype = str(resp.headers.get("Content-Type") or "").lower()
            raw = resp.read(_FETCH_BYTES_CAP)
            final_url = resp.geturl()
    except Exception as exc:  # noqa: BLE001 - the network is allowed to fail
        logger.warning("fetch_url failed %s: %s", url, exc)
        return ToolResult.error(f"Could not open that page: {exc}")

    if "application/pdf" in ctype:
        return ToolResult.error(
            "That link is a PDF. Ask them to save it and name the path, then "
            "read_file can open it."
        )
    if ctype and not any(t in ctype for t in ("text/", "json", "xml")):
        return ToolResult.error(f"That link is {ctype.split(';')[0]}, which is not readable text.")

    charset = "utf-8"
    if "charset=" in ctype:
        charset = ctype.split("charset=", 1)[1].split(";")[0].strip() or "utf-8"
    try:
        text = raw.decode(charset, errors="replace")
    except LookupError:
        text = raw.decode("utf-8", errors="replace")

    if "html" in ctype or text.lstrip()[:200].lower().startswith(("<!doctype", "<html")):
        try:
            from .files import _extract_html

            text = _extract_html(text)
        except Exception as exc:  # noqa: BLE001
            logger.warning("fetch_url extract failed: %s", exc)

    text = text.strip()
    if not text:
        return ToolResult.error(
            "That page had no readable text. It may be built entirely by script."
        )
    body = text[:max_chars]
    truncated = len(text) > len(body)
    logger.info("fetch_url ok %s (%d chars%s)", final_url, len(body), ", truncated" if truncated else "")
    return ToolResult(
        content=(
            f"Page: {final_url}\nChars: {len(body)}"
            + (" (truncated)" if truncated else "")
            + "\n---\n"
            + body
        ),
        data={"url": final_url, "chars": len(body), "truncated": truncated},
    )
