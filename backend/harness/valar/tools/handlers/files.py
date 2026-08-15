"""Local document tools under allow-listed roots.

``read_file`` opens an operator-named path. ``write_file`` drafts a *new*
file beside a source (never overwrites the source). The model passes only
short ``instructions``; the harness re-reads the source and asks the brain
for the draft body. Putting full documents in tool-call JSON breaks
llama-server argument parsing (live 2026-08-11).

Text sources keep the same type; HTML and PDF sources always draft as
Markdown. PDF text via pypdf on read only; writes are UTF-8 text.
"""

from __future__ import annotations

import asyncio
import html.parser
import logging
import re
import uuid
from datetime import datetime
from pathlib import Path

import httpx
import yaml

from ...config.settings import HearthConfigError, hearth_engram
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.files")

_HEARTH_ROOT = Path(__file__).resolve().parents[5]
_ROOTS_FILE = Path(__file__).resolve().parents[1] / "file_roots.yaml"
_GRANTS_FILE = Path(__file__).resolve().parents[1] / "file_grants.yaml"

# In-memory permission requests the chat card Approve/Deny buttons resolve.
# Optional "future" is an asyncio.Future the tool loop awaits so Approve
# resumes the same turn instead of asking the operator to speak again.
_PENDING: dict[str, dict] = {}
_PERMISSION_WAIT_S = 300.0
_LIST_DIR_CAP = 200

_DEFAULT_MAX_CHARS = 12_000
_HARD_MAX_CHARS = 20_000
_MAX_WRITE_CHARS = 200_000
_MAX_INSTRUCTIONS_CHARS = 2_000
_SOURCE_CONTEXT_CHARS = 14_000
_DRAFT_MAX_TOKENS = 4_096

_TEXT_SUFFIXES = frozenset(
    {
        ".txt",
        ".md",
        ".markdown",
        ".json",
        ".yaml",
        ".yml",
        ".csv",
        ".log",
        ".py",
        ".ts",
        ".tsx",
        ".js",
        ".jsx",
        ".css",
        ".toml",
        ".ini",
        ".cfg",
        ".xml",
        ".svg",
    }
)
_HTML_SUFFIXES = frozenset({".html", ".htm"})
_PDF_SUFFIXES = frozenset({".pdf"})
_ALLOWED_SUFFIXES = _TEXT_SUFFIXES | _HTML_SUFFIXES | _PDF_SUFFIXES
_WRITABLE_SUFFIXES = _TEXT_SUFFIXES | _HTML_SUFFIXES

_DRIVE_RE = re.compile(r"^([A-Za-z]):[/\\]")
_SAFE_DEST_NAME_RE = re.compile(r"^[^/\\]+$")
_MD_DRAFT_SUFFIXES = frozenset({".md", ".markdown"})
_HTML_DOC_RE = re.compile(
    r"<!DOCTYPE\s+html|<html[\s>]|<head[\s>]|<body[\s>]|<style[\s>]",
    re.IGNORECASE,
)


def _looks_like_html_document(content: str) -> bool:
    """True when content is a full HTML page (unsafe for tool-call JSON)."""
    head = (content or "")[:4000]
    return bool(_HTML_DOC_RE.search(head))


def _draft_suffix_for_source(source_suffix: str) -> str:
    """HTML/PDF sources draft as .md; everything else keeps the source type."""
    if source_suffix in _HTML_SUFFIXES or source_suffix in _PDF_SUFFIXES:
        return ".md"
    return source_suffix


def _strip_code_fence(text: str) -> str:
    """Drop a single surrounding markdown fence if the model wraps the draft."""
    s = (text or "").strip()
    if not s.startswith("```"):
        return s
    lines = s.splitlines()
    if len(lines) < 2:
        return s
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


async def _generate_draft_body(
    source_text: str,
    instructions: str,
    dest_suffix: str,
) -> str:
    """Ask the resident brain for the draft body (normal completion, not tools)."""
    from ...config.settings import BrainConfig

    cfg = BrainConfig()
    base = cfg.base_url.rstrip("/")
    url = f"{base}/chat/completions"
    fmt = "Markdown" if dest_suffix in _MD_DRAFT_SUFFIXES else f"{dest_suffix.lstrip('.')} text"
    # No source means authoring rather than revising: same generation seam, same
    # rule that the body never travels through tool-call JSON.
    if source_text.strip():
        system = (
            "You revise documents for the operator. Output ONLY the full revised "
            f"document as {fmt}. No preamble, no closing remarks, no HTML tags, "
            "no <!DOCTYPE>, no <style> blocks. If the source was HTML, rewrite it "
            "as clean Markdown."
        )
        user = (
            f"INSTRUCTIONS:\n{instructions}\n\n"
            f"SOURCE:\n{source_text[:_SOURCE_CONTEXT_CHARS]}\n"
        )
    else:
        system = (
            "You write documents for the operator. Output ONLY the finished "
            f"document as {fmt}. No preamble, no closing remarks, no HTML tags, "
            "no <!DOCTYPE>, no <style> blocks. Give it a title heading and a "
            "sensible structure for what was asked."
        )
        user = f"WRITE THIS DOCUMENT:\n{instructions}\n"
    payload: dict = {
        "stream": False,
        "max_tokens": max(_DRAFT_MAX_TOKENS, cfg.max_tokens or 0),
        "temperature": min(cfg.temperature, 0.7),
        # Draft body must land in content; Gemma reasoning can eat the whole
        # budget and leave content empty (live probe 2026-08-11).
        "chat_template_kwargs": {"enable_thinking": False},
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    if cfg.model:
        payload["model"] = cfg.model
    timeout = httpx.Timeout(cfg.request_timeout_s)
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(url, json=payload)
        if resp.status_code != 200:
            raise RuntimeError(
                f"draft generation failed ({resp.status_code}): {resp.text[:300]}"
            )
        data = resp.json()
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("draft generation returned no choices")
    choice = choices[0] or {}
    message = choice.get("message") or {}
    body = _strip_code_fence(str(message.get("content") or ""))
    if not body:
        raise RuntimeError(
            "draft generation returned empty content "
            f"(finish_reason={choice.get('finish_reason')!r})"
        )
    if _looks_like_html_document(body):
        raise RuntimeError(
            "draft generation returned HTML; refusing to write. Try again with "
            "clearer instructions asking for Markdown only."
        )
    if len(body) > _MAX_WRITE_CHARS:
        raise RuntimeError(
            f"draft generation too large ({len(body)} chars; cap {_MAX_WRITE_CHARS})"
        )
    return body


def _to_posix_path(raw: str) -> Path:
    """Normalize a Windows or WSL path string into a Path usable on this host."""
    s = (raw or "").strip().strip('"').strip("'")
    if not s:
        raise ValueError("empty path")
    s = s.replace("\\", "/")
    m = _DRIVE_RE.match(s)
    if m:
        drive = m.group(1).lower()
        rest = s[m.end() :]
        wsl = Path(f"/mnt/{drive}") / rest
        win = Path(f"{drive.upper()}:/{rest}")
        if wsl.exists():
            return wsl
        if win.exists():
            return win
        # Prefer the WSL mount when Valar is running under WSL.
        if Path(f"/mnt/{drive}").is_dir():
            return wsl
        return win
    return Path(s)


def _load_roots() -> list[tuple[str, Path]]:
    """Load allow-listed roots from YAML; skip missing entries with a warning."""
    roots: list[tuple[str, Path]] = []
    try:
        data = yaml.safe_load(_ROOTS_FILE.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001 -- degrade to built-in defaults
        logger.warning("file_roots.yaml unreadable (%s); using built-in defaults", exc)
        data = {"roots": [{"name": "hearth", "path": str(_HEARTH_ROOT)}]}
    for entry in data.get("roots") or []:
        name = str(entry.get("name") or "").strip()
        path_s = str(entry.get("path") or "").strip()
        if not name or not path_s:
            continue
        try:
            p = _to_posix_path(path_s).resolve()
        except Exception as exc:  # noqa: BLE001
            logger.warning("root %s path invalid (%s): %s", name, path_s, exc)
            continue
        if not p.exists():
            logger.warning("root %s missing on disk: %s", name, p)
            continue
        roots.append((name, p))
    for name, p in _load_grants():
        if not any(r == p for _, r in roots):
            roots.append((name, p))
    # The memory tree is always readable, wherever the operator put it. Asked
    # of the configuration rather than searched for: a candidate list is how a
    # fresh install silently adopts whichever brain happens to be on the
    # machine, which is the one thing a file allow-list must never do.
    try:
        engram = hearth_engram().resolve()
        if engram.is_dir() and not any(r == engram for _, r in roots):
            roots.append(("engram", engram))
    except HearthConfigError as exc:
        logger.info("no memory tree configured for file reads: %s", exc)
    except Exception as exc:  # noqa: BLE001 -- roots are additive
        logger.warning("memory tree root unavailable: %s", exc)
    return roots


def _load_grants() -> list[tuple[str, Path]]:
    """Operator-approved roots written by the permission card. Missing file = none."""
    if not _GRANTS_FILE.exists():
        return []
    try:
        data = yaml.safe_load(_GRANTS_FILE.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001
        logger.warning("file_grants.yaml unreadable (%s)", exc)
        return []
    out: list[tuple[str, Path]] = []
    for entry in data.get("grants") or []:
        name = str(entry.get("name") or "").strip()
        path_s = str(entry.get("path") or "").strip()
        if not name or not path_s:
            continue
        try:
            p = _to_posix_path(path_s).resolve()
        except Exception:
            continue
        if p.exists():
            out.append((name, p))
    return out


def _grant_target(path: Path) -> Path:
    """The folder the operator would be granting: the dir itself, or a file's parent."""
    if path.exists() and path.is_file():
        return path.parent
    return path


def _permission_result(path: Path, action: str) -> ToolResult:
    """Ask the operator to grant a folder; emit the chat permission card."""
    target = _grant_target(path)
    request_id = uuid.uuid4().hex[:12]
    display = _display_path(target)
    _PENDING[request_id] = {
        "path": str(target),
        "display": display,
        "action": action,
        "status": "pending",
    }
    logger.info("file permission requested id=%s action=%s path=%s", request_id, action, target)
    return ToolResult(
        content=f"Waiting for the operator to approve access to {display}.",
        ok=False,
        data={
            "await_permission": True,
            "request_id": request_id,
            "ui_component": {
                "version": 1,
                "type": "permission_card",
                "props": {
                    "request_id": request_id,
                    "path": display,
                    "action": action,
                    "status": "pending",
                },
            },
        },
    )


def decide(request_id: str, approve: bool) -> dict:
    """Approve or deny a pending folder grant. Called from POST /files/decide."""
    req = _PENDING.get(request_id)
    if req is None:
        return {"ok": False, "error": "That permission request is no longer open."}
    if req.get("status") != "pending":
        return {"ok": True, "status": req.get("status"), "path": req.get("display")}
    if not approve:
        req["status"] = "denied"
        logger.info("file permission denied id=%s path=%s", request_id, req.get("path"))
        _resolve_waiter(req, "denied")
        return {"ok": True, "status": "denied", "path": req.get("display")}
    raw = str(req.get("path") or "")

    def _fail(message: str) -> dict:
        """The operator said yes and it could not be done.

        Recorded as `failed`, never as `denied`. They are not the same event
        and the model must not be handed the wrong one: told "denied" after an
        approval, it apologises for a permission problem that does not exist
        while the real reason goes unsaid (live 2026-08-15).
        """
        req["status"] = "failed"
        req["error"] = message
        logger.info("file permission failed id=%s: %s", request_id, message)
        _resolve_waiter(req, "failed")
        return {"ok": False, "status": "failed", "error": message}

    try:
        target = _to_posix_path(raw).resolve()
    except Exception as exc:  # noqa: BLE001
        return _fail(f"Could not resolve that path: {exc}")
    # A create grant is the one case where the path is SUPPOSED to be absent.
    # Approving it makes the folder, here, before the grant is recorded: a
    # grant is reloaded as a root and roots that do not exist are dropped, so a
    # grant for a folder nobody created would be forgotten the instant it was
    # given, and the retry would raise the same card again.
    if not target.exists():
        if str(req.get("action") or "") != "create":
            return _fail(f"Nothing exists at {_display_path(target)}.")
        try:
            target.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # noqa: BLE001
            return _fail(f"Could not create {_display_path(target)}: {exc}")
        logger.info("file permission created folder id=%s path=%s", request_id, target)
    name = re.sub(r"[^a-z0-9]+", "-", target.name.lower()).strip("-") or "grant"
    grants = []
    if _GRANTS_FILE.exists():
        try:
            grants = list(
                (yaml.safe_load(_GRANTS_FILE.read_text(encoding="utf-8")) or {}).get("grants")
                or []
            )
        except Exception:
            grants = []
    already = any(
        str(entry.get("path") or "").replace("\\", "/").lower()
        == str(target).replace("\\", "/").lower()
        for entry in grants
    )
    if not already:
        grants.append(
            {
                "name": name,
                "path": str(target).replace("\\", "/"),
                "granted_at": datetime.now().isoformat(timespec="seconds"),
            }
        )
        _GRANTS_FILE.write_text(
            yaml.safe_dump({"grants": grants}, sort_keys=False),
            encoding="utf-8",
        )
    req["status"] = "granted"
    logger.info("file permission granted id=%s path=%s", request_id, target)
    _resolve_waiter(req, "granted")
    return {"ok": True, "status": "granted", "path": _display_path(target)}


def grant_state(request_id: str) -> dict:
    req = _PENDING.get(request_id)
    if req is None:
        return {"request_id": request_id, "status": "unknown"}
    return {
        "request_id": request_id,
        "status": req.get("status") or "pending",
        "path": req.get("display") or "",
        "action": req.get("action") or "read",
    }


def _resolve_waiter(req: dict, status: str) -> None:
    fut = req.get("future")
    if fut is None or getattr(fut, "done", lambda: True)():
        return

    def _set() -> None:
        if not fut.done():
            fut.set_result(status)

    loop = fut.get_loop()
    if loop.is_running():
        loop.call_soon_threadsafe(_set)
    else:
        _set()


def decision_error(request_id: str) -> str:
    """Why an approved request could not be honoured, for the tool loop to
    report instead of guessing at a reason."""
    req = _PENDING.get(request_id) or {}
    return str(req.get("error") or "")


async def wait_for_decision(request_id: str, timeout: float = _PERMISSION_WAIT_S) -> str:
    """Park the tool loop until Approve/Deny, or time out."""
    req = _PENDING.get(request_id)
    if req is None:
        return "unknown"
    status = str(req.get("status") or "pending")
    if status != "pending":
        return status
    loop = asyncio.get_running_loop()
    fut = req.get("future")
    if fut is None or getattr(fut, "done", lambda: True)():
        fut = loop.create_future()
        req["future"] = fut
    try:
        return str(await asyncio.wait_for(fut, timeout))
    except asyncio.TimeoutError:
        if req.get("status") == "pending":
            req["status"] = "timeout"
        logger.info("file permission timed out id=%s", request_id)
        return "timeout"


def _under_root(path: Path, roots: list[tuple[str, Path]]) -> str | None:
    """Return the root name if path is contained, else None."""
    for name, root in roots:
        try:
            if path == root or path.is_relative_to(root):
                return name
        except (ValueError, OSError):
            continue
    return None


def _display_path(path: Path) -> str:
    """Prefer a Windows-looking path when reporting back to the model."""
    s = str(path)
    m = re.match(r"^/mnt/([a-z])/(.*)$", s.replace("\\", "/"))
    if m:
        return f"{m.group(1).upper()}:\\{m.group(2).replace('/', chr(92))}"
    return s


class _HTMLTextExtractor(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []
        self._skip = 0
        self.title = ""
        self._in_title = False

    def handle_starttag(self, tag: str, attrs) -> None:  # noqa: ANN001
        t = tag.lower()
        if t in ("script", "style", "noscript"):
            self._skip += 1
        if t == "title":
            self._in_title = True
        if t in ("p", "div", "br", "li", "h1", "h2", "h3", "h4", "tr", "section"):
            self._chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if t in ("script", "style", "noscript") and self._skip:
            self._skip -= 1
        if t == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._skip:
            return
        if self._in_title:
            self.title += data
            return
        text = data.strip()
        if text:
            self._chunks.append(text + " ")

    def text(self) -> str:
        body = re.sub(r"[ \t]+\n", "\n", "".join(self._chunks))
        body = re.sub(r"\n{3,}", "\n\n", body).strip()
        if self.title.strip():
            return f"{self.title.strip()}\n\n{body}".strip()
        return body


def _extract_html(raw: str) -> str:
    parser = _HTMLTextExtractor()
    parser.feed(raw)
    parser.close()
    return parser.text()


def _extract_pdf(path: Path) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError(
            "PDF support needs the pypdf package (pip install pypdf)."
        ) from exc
    reader = PdfReader(str(path))
    parts: list[str] = []
    for page in reader.pages:
        try:
            text = page.extract_text() or ""
        except Exception as exc:  # noqa: BLE001 -- one bad page must not kill the read
            logger.warning("pdf page extract failed %s: %s", path, exc)
            continue
        text = text.strip()
        if text:
            parts.append(text)
    body = "\n\n".join(parts).strip()
    if not body:
        raise ValueError(
            "PDF had no extractable text (likely a scanned image). OCR is not available yet."
        )
    return body


def _extract(path: Path) -> tuple[str, str]:
    """Return (type_label, full_text)."""
    suffix = path.suffix.lower()
    if suffix in _PDF_SUFFIXES:
        return "pdf", _extract_pdf(path)
    raw = path.read_text(encoding="utf-8", errors="replace")
    if suffix in _HTML_SUFFIXES:
        return "html", _extract_html(raw)
    label = suffix.lstrip(".") or "text"
    return label, raw


def _unique_draft_path(directory: Path, stem: str, suffix: str) -> Path:
    """Pick ``stem-draft.suffix``, then ``stem-draft-2.suffix``, ..."""
    candidate = directory / f"{stem}-draft{suffix}"
    if not candidate.exists():
        return candidate
    n = 2
    while True:
        candidate = directory / f"{stem}-draft-{n}{suffix}"
        if not candidate.exists():
            return candidate
        n += 1
        if n > 1000:
            raise RuntimeError("too many existing draft files beside the source")


def read_file(args: dict) -> ToolResult:
    """Read a local file the operator named, if it sits under an allowed root."""
    raw_path = str((args or {}).get("path") or "").strip()
    if not raw_path:
        return ToolResult.error("read_file needs a path.")

    try:
        offset = int((args or {}).get("offset") or 0)
    except (TypeError, ValueError):
        return ToolResult.error("offset must be an integer.")
    if offset < 0:
        return ToolResult.error("offset must be >= 0.")

    try:
        max_chars = int((args or {}).get("max_chars") or _DEFAULT_MAX_CHARS)
    except (TypeError, ValueError):
        return ToolResult.error("max_chars must be an integer.")
    max_chars = max(1, min(max_chars, _HARD_MAX_CHARS))

    roots = _load_roots()
    if not roots:
        return ToolResult.error(
            "No readable file roots are configured. Ask the operator to check file_roots.yaml."
        )

    try:
        candidate = _to_posix_path(raw_path).resolve()
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not resolve that path: {exc}")

    # Existence before permission, same rule as list_dir: a file that is not
    # there is a plain fact, not something to ask consent about.
    if not candidate.exists():
        return ToolResult.error(
            f"No file at {_display_path(candidate)}. It does not exist; this is "
            "not a permission problem."
        )

    root_name = _under_root(candidate, roots)
    if root_name is None:
        return _permission_result(candidate, "read")

    if not candidate.is_file():
        return ToolResult.error(
            f"{_display_path(candidate)} is a directory. Call list_dir on it, "
            "then read_file on each file you need."
        )

    suffix = candidate.suffix.lower()
    if suffix not in _ALLOWED_SUFFIXES:
        kinds = ", ".join(sorted({s.lstrip('.') for s in _ALLOWED_SUFFIXES}))
        return ToolResult.error(
            f"Unsupported file type '{suffix or '(none)'}'. Supported: {kinds}."
        )

    try:
        type_label, full = _extract(candidate)
    except Exception as exc:  # noqa: BLE001 -- surface as a tool error for the model
        logger.warning("read_file extract failed %s: %s", candidate, exc)
        return ToolResult.error(f"Could not read {_display_path(candidate)}: {exc}")

    total = len(full)
    if offset >= total:
        return ToolResult.error(
            f"offset {offset} is past the end of the file ({total} characters)."
        )
    body = full[offset : offset + max_chars]
    truncated = offset + len(body) < total

    header = (
        f"File: {_display_path(candidate)}\n"
        f"Type: {type_label}\n"
        f"Root: {root_name}\n"
        f"Chars: {len(body)}/{total}"
        + (f" (truncated; pass offset={offset + len(body)} to continue)" if truncated else "")
        + "\n---\n"
    )
    logger.info(
        "read_file ok root=%s type=%s chars=%s/%s path=%s",
        root_name,
        type_label,
        len(body),
        total,
        candidate,
    )
    return ToolResult(
        content=header + body,
        data={
            "path": _display_path(candidate),
            "root": root_name,
            "type": type_label,
            "chars_returned": len(body),
            "chars_total": total,
            "truncated": truncated,
            "offset": offset,
        },
    )


async def write_file(args: dict) -> ToolResult:
    """Write a new draft beside an existing source under allowed roots.

    The model supplies short ``instructions`` only. The harness re-reads the
    source and generates the draft body via a normal (non-tool) brain call so
    large documents never enter tool-call JSON.
    """
    raw_source = str((args or {}).get("source") or "").strip()
    instructions = str((args or {}).get("instructions") or "").strip()
    dest_name = str((args or {}).get("dest_name") or "").strip()

    if not raw_source:
        return ToolResult.error("write_file needs a source path.")
    if (args or {}).get("content") not in (None, ""):
        return ToolResult.error(
            "Do not pass content. Pass short instructions only; the harness "
            "writes the draft body (tool-call JSON cannot carry full documents)."
        )
    if not instructions:
        return ToolResult.error(
            "write_file needs short instructions describing the revision."
        )
    if len(instructions) > _MAX_INSTRUCTIONS_CHARS:
        return ToolResult.error(
            f"instructions too long ({len(instructions)} chars; "
            f"cap {_MAX_INSTRUCTIONS_CHARS}). Summarize the revision."
        )

    roots = _load_roots()
    if not roots:
        return ToolResult.error(
            "No writable file roots are configured. Ask the operator to check file_roots.yaml."
        )

    try:
        source = _to_posix_path(raw_source).resolve()
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not resolve that source path: {exc}")

    root_name = _under_root(source, roots)
    if root_name is None:
        return _permission_result(source, "write")

    if not source.exists():
        return ToolResult.error(f"No source file at {_display_path(source)}.")
    if not source.is_file():
        return ToolResult.error(
            f"{_display_path(source)} is a directory; name a specific file."
        )

    source_suffix = source.suffix.lower()
    if source_suffix not in _ALLOWED_SUFFIXES:
        kinds = ", ".join(sorted({s.lstrip('.') for s in _ALLOWED_SUFFIXES}))
        return ToolResult.error(
            f"Unsupported source type '{source_suffix or '(none)'}'. Supported: {kinds}."
        )

    dest_suffix = _draft_suffix_for_source(source_suffix)
    if dest_suffix not in _WRITABLE_SUFFIXES and dest_suffix not in _MD_DRAFT_SUFFIXES:
        return ToolResult.error(
            f"Cannot draft type '{dest_suffix or '(none)'}' from this source."
        )

    parent = source.parent
    parent_resolved = parent.resolve()
    if dest_name:
        if not _SAFE_DEST_NAME_RE.match(dest_name) or dest_name in (".", ".."):
            return ToolResult.error(
                "dest_name must be a plain filename in the source folder (no path separators)."
            )
        dest = (parent / dest_name).resolve()
        got = dest.suffix.lower()
        if got != dest_suffix and not (
            dest_suffix in _MD_DRAFT_SUFFIXES and got in _MD_DRAFT_SUFFIXES
        ):
            return ToolResult.error(
                f"dest_name must use type ({dest_suffix}) for this source; "
                f"got '{got or '(none)'}'."
            )
        if dest.exists():
            return ToolResult.error(
                f"{_display_path(dest)} already exists; pick another dest_name or omit it "
                "to auto-name a draft."
            )
    else:
        try:
            dest = _unique_draft_path(parent, source.stem, dest_suffix).resolve()
        except Exception as exc:  # noqa: BLE001
            return ToolResult.error(f"Could not pick a draft name: {exc}")

    if dest.parent.resolve() != parent_resolved:
        return ToolResult.error(
            "Destination must stay in the same folder as the source."
        )
    if _under_root(dest, roots) is None:
        return ToolResult.error("Destination resolved outside allowed folders.")
    if dest == source:
        return ToolResult.error("Refusing to overwrite the source file.")

    try:
        _type_label, source_text = _extract(source)
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not read source {_display_path(source)}: {exc}")
    if not source_text.strip():
        return ToolResult.error("Source file has no extractable text to draft from.")

    try:
        content = await _generate_draft_body(source_text, instructions, dest_suffix)
    except Exception as exc:  # noqa: BLE001
        logger.warning("write_file generate failed source=%s: %s", source, exc)
        return ToolResult.error(f"Could not generate draft: {exc}")

    try:
        dest.write_text(content, encoding="utf-8", newline="\n")
    except Exception as exc:  # noqa: BLE001
        logger.warning("write_file failed %s: %s", dest, exc)
        return ToolResult.error(f"Could not write {_display_path(dest)}: {exc}")

    out_type = dest.suffix.lstrip(".").lower() or "text"
    logger.info(
        "write_file ok root=%s type=%s chars=%s dest=%s source=%s",
        root_name,
        out_type,
        len(content),
        dest,
        source,
    )
    shown = _display_path(dest)
    return ToolResult(
        content=(
            f"Wrote draft: {shown}\n"
            f"Type: {out_type}\n"
            f"Root: {root_name}\n"
            f"Chars: {len(content)}\n"
            f"Source: {_display_path(source)}\n"
            "Speak only a short confirmation naming this path. "
            "Never speak the draft body, HTML, or CSS. "
            "Do not invent a path — only this one was written."
        ),
        data={
            "path": shown,
            "source": _display_path(source),
            "root": root_name,
            "type": out_type,
            "chars": len(content),
        },
    )


async def new_file(args: dict) -> ToolResult:
    """Write a NEW document at a path the operator named.

    The other half of write_file, which only ever drafts beside something that
    already exists. Asked for "a recipe in a new folder at D:/Recipes", the
    house had no tool that could do it and went looking with list_dir instead
    (live 2026-08-15), which is how a missing capability comes back as a
    permission complaint.

    Same contract as write_file: the model passes a destination and short
    instructions, never a body. The harness writes what the brain composes.
    """
    raw_path = str((args or {}).get("path") or "").strip()
    instructions = str((args or {}).get("instructions") or "").strip()

    if not raw_path:
        return ToolResult.error("new_file needs a path for the new document.")
    if (args or {}).get("content") not in (None, ""):
        return ToolResult.error(
            "Do not pass content. Pass short instructions only; the harness "
            "writes the body (tool-call JSON cannot carry full documents)."
        )
    if not instructions:
        return ToolResult.error(
            "new_file needs short instructions describing what to write."
        )
    if len(instructions) > _MAX_INSTRUCTIONS_CHARS:
        return ToolResult.error(
            f"instructions too long ({len(instructions)} chars; "
            f"cap {_MAX_INSTRUCTIONS_CHARS})."
        )

    roots = _load_roots()
    if not roots:
        return ToolResult.error(
            "No writable file roots are configured. Ask the operator to check file_roots.yaml."
        )

    try:
        dest = _to_posix_path(raw_path).resolve()
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not resolve that path: {exc}")

    # A path with no extension is a filename the model forgot to finish, not a
    # folder to write into. Markdown is the house default.
    if not dest.suffix:
        dest = dest.with_suffix(".md")
    suffix = dest.suffix.lower()
    if suffix not in _WRITABLE_SUFFIXES:
        kinds = ", ".join(sorted({s.lstrip('.') for s in _WRITABLE_SUFFIXES}))
        return ToolResult.error(
            f"Cannot write type '{suffix}'. Supported: {kinds}."
        )
    if dest.exists():
        return ToolResult.error(
            f"{_display_path(dest)} already exists. Use write_file to revise it, "
            "or pick another name."
        )

    parent = dest.parent
    if _under_root(parent, roots) is None:
        # Outside the allow-list. Which question to ask depends on whether the
        # folder is there: consent to open it, or consent to create it.
        return _permission_result(parent, "write" if parent.is_dir() else "create")

    if not parent.is_dir():
        try:
            parent.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # noqa: BLE001
            return ToolResult.error(
                f"Could not create {_display_path(parent)}: {exc}"
            )
        logger.info("new_file created folder %s", parent)

    try:
        content = await _generate_draft_body("", instructions, suffix)
    except Exception as exc:  # noqa: BLE001
        logger.warning("new_file generate failed dest=%s: %s", dest, exc)
        return ToolResult.error(f"Could not write that document: {exc}")

    try:
        dest.write_text(content, encoding="utf-8", newline="\n")
    except Exception as exc:  # noqa: BLE001
        logger.warning("new_file failed %s: %s", dest, exc)
        return ToolResult.error(f"Could not write {_display_path(dest)}: {exc}")

    out_type = suffix.lstrip(".") or "text"
    root_name = _under_root(dest, roots) or ""
    logger.info(
        "new_file ok root=%s type=%s chars=%s dest=%s", root_name, out_type, len(content), dest
    )
    shown = _display_path(dest)
    return ToolResult(
        content=(
            f"Wrote file: {shown}\n"
            f"Type: {out_type}\n"
            f"Root: {root_name}\n"
            f"Chars: {len(content)}\n"
            "Speak only a short confirmation naming this path. "
            "Never speak the body back. "
            "Do not invent a path -- only this one was written."
        ),
        data={
            "path": shown,
            "root": root_name,
            "type": out_type,
            "chars": len(content),
            "created": True,
        },
    )


def list_dir(args: dict) -> ToolResult:
    """List files and subfolders in an operator-named directory."""
    raw_path = str((args or {}).get("path") or "").strip()
    if not raw_path:
        return ToolResult.error("list_dir needs a path.")

    roots = _load_roots()
    if not roots:
        return ToolResult.error(
            "No readable file roots are configured. Ask the operator to check file_roots.yaml."
        )

    try:
        candidate = _to_posix_path(raw_path).resolve()
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not resolve that path: {exc}")

    # Existence first, permission second. A folder that is not there is not a
    # consent question, and asking one produces the worst possible exchange:
    # the operator approves, the approval cannot be honoured, and the model is
    # told it was refused (live 2026-08-15, "D:/Recipes").
    if not candidate.exists():
        return ToolResult.error(
            f"Nothing at {_display_path(candidate)}. The folder does not exist; "
            "this is not a permission problem. Say so plainly, and offer to "
            "create it if that is what they meant."
        )

    if _under_root(candidate, roots) is None:
        return _permission_result(candidate, "list")

    if candidate.is_file():
        return ToolResult.error(
            f"{_display_path(candidate)} is a file. Call read_file on it."
        )
    if not candidate.is_dir():
        return ToolResult.error(f"{_display_path(candidate)} is not a directory.")

    try:
        entries = sorted(candidate.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except OSError as exc:
        return ToolResult.error(f"Could not list {_display_path(candidate)}: {exc}")

    truncated = len(entries) > _LIST_DIR_CAP
    entries = entries[:_LIST_DIR_CAP]
    lines = [f"Directory: {_display_path(candidate)}", f"Entries: {len(entries)}"]
    files: list[str] = []
    dirs: list[str] = []
    for item in entries:
        kind = "dir" if item.is_dir() else "file"
        shown = _display_path(item)
        if item.is_dir():
            dirs.append(shown)
            lines.append(f"- {item.name}/  {kind}")
        else:
            files.append(shown)
            size = ""
            try:
                n = item.stat().st_size
                size = f"  {n} bytes"
            except OSError:
                pass
            lines.append(f"- {item.name}  {kind}{size}")
    if truncated:
        lines.append(f"(truncated to {_LIST_DIR_CAP} entries)")
    if files:
        lines.append(
            "Call read_file on each file you need, using the full path."
        )
    logger.info(
        "list_dir ok path=%s files=%d dirs=%d",
        candidate,
        len(files),
        len(dirs),
    )
    return ToolResult(
        content="\n".join(lines),
        data={
            "path": _display_path(candidate),
            "files": files,
            "dirs": dirs,
            "truncated": truncated,
        },
    )
