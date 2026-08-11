"""read_file -- open an operator-named local document under allow-listed roots.

The model may pass a path (Windows or WSL). The handler normalizes, resolves,
and rejects anything outside ``file_roots.yaml``. That keeps the house
grounding rule (config owns the boundary) while matching the conversational
shape where the operator points at a resume or note by path.

Standalone: no Valar state, no websocket. Sync handler -- the registry runs it
in a thread. PDF text via pypdf; HTML stripped with the stdlib parser; other
text-like types read as UTF-8.
"""

from __future__ import annotations

import html.parser
import logging
import re
from pathlib import Path

import yaml

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.files")

_HEARTH_ROOT = Path(__file__).resolve().parents[5]
_ROOTS_FILE = Path(__file__).resolve().parents[1] / "file_roots.yaml"

_DEFAULT_MAX_CHARS = 12_000
_HARD_MAX_CHARS = 20_000

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

_DRIVE_RE = re.compile(r"^([A-Za-z]):[/\\]")


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
        data = {
            "roots": [
                {"name": "career", "path": "D:/Tools/Career"},
                {"name": "engram", "path": "D:/Tools/personalAI/Engram"},
                {"name": "hearth", "path": str(_HEARTH_ROOT)},
            ]
        }
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
    # Engram junction inside the repo is often the live path even when the
    # personalAI absolute path is listed; add it when present.
    for candidate in (
        _HEARTH_ROOT / "Engram",
        Path("D:/Tools/personalAI/Engram"),
        Path("/mnt/d/Tools/personalAI/Engram"),
    ):
        try:
            if (candidate / "Thoughts").is_dir():
                resolved = candidate.resolve()
                if not any(r == resolved for _, r in roots):
                    roots.append(("engram", resolved))
                break
        except OSError:
            continue
    return roots


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

    root_name = _under_root(candidate, roots)
    if root_name is None:
        allowed = ", ".join(f"{n} ({_display_path(p)})" for n, p in roots)
        return ToolResult.error(
            f"That path is outside the house's allowed folders. Allowed: {allowed}."
        )

    if not candidate.exists():
        return ToolResult.error(f"No file at {_display_path(candidate)}.")
    if not candidate.is_file():
        return ToolResult.error(
            f"{_display_path(candidate)} is a directory; name a specific file."
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
