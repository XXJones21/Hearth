"""Tools that reach the operator's actual desktop.

Everything else in the house works on files, memory, or the network. These
three hand something to the machine the person is sitting at: the clipboard
they paste from, the mail client they send from, the file browser they look
in.

That makes them the tools most dependent on where the house is RUNNING. It
sits in the operator's own session when the desktop client starts it, which
is the normal arrangement and the one these assume. Started headless, as a
service with no desktop, they fail; each one says so plainly rather than
reporting success into a void.

Nothing here sends anything. draft_email opens a composer with the words in
it and stops, because sending is a promise about someone else's inbox and
the house should not be making those on its own.
"""

from __future__ import annotations

import logging
import platform
import subprocess
import urllib.parse
from pathlib import Path

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.desktop")

_CLIP_MAX = 20_000
_MAIL_BODY_MAX = 8_000
_TIMEOUT_S = 10


def _windows() -> bool:
    return platform.system().lower().startswith("win")


def _run(cmd: list[str], stdin: str | None = None) -> tuple[bool, str]:
    try:
        proc = subprocess.run(
            cmd,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_S,
            check=False,
        )
    except FileNotFoundError:
        return False, f"{cmd[0]} is not installed on this machine"
    except subprocess.TimeoutExpired:
        return False, f"{cmd[0]} did not answer"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)
    if proc.returncode != 0:
        return False, (proc.stderr or proc.stdout or "").strip()[:200] or "failed"
    return True, proc.stdout


def _os_open(target: str) -> tuple[bool, str]:
    """Hand a path or a URL to whatever the operator has set to open it."""
    if _windows():
        # start needs a title argument first, or it eats a quoted target.
        ok, err = _run(["cmd", "/c", "start", "", target])
        return ok, err
    if platform.system().lower() == "darwin":
        return _run(["open", target])
    return _run(["xdg-open", target])


def clipboard(args: dict) -> ToolResult:
    """args: {action: read|write, text?: str}. The shortest path between the
    house and every other program on the machine."""
    action = str((args or {}).get("action") or "read").strip().lower()
    if action.startswith("r"):
        if _windows():
            ok, out = _run(["powershell", "-NoProfile", "-Command", "Get-Clipboard -Raw"])
        elif platform.system().lower() == "darwin":
            ok, out = _run(["pbpaste"])
        else:
            ok, out = _run(["xclip", "-selection", "clipboard", "-o"])
        if not ok:
            return ToolResult.error(f"I could not read the clipboard: {out}")
        text = (out or "").strip()
        if not text:
            return ToolResult(content="The clipboard is empty.", data={"text": ""})
        clipped = text[:_CLIP_MAX]
        return ToolResult(
            content=f"Clipboard ({len(clipped)} chars):\n---\n{clipped}",
            data={"text": clipped, "truncated": len(text) > len(clipped)},
        )

    text = str((args or {}).get("text") or "")
    if not text.strip():
        return ToolResult.error("There was nothing to put on the clipboard.")
    text = text[:_CLIP_MAX]
    if _windows():
        ok, err = _run(
            ["powershell", "-NoProfile", "-Command", "$input | Set-Clipboard"], stdin=text
        )
    elif platform.system().lower() == "darwin":
        ok, err = _run(["pbcopy"], stdin=text)
    else:
        ok, err = _run(["xclip", "-selection", "clipboard"], stdin=text)
    if not ok:
        return ToolResult.error(f"I could not write to the clipboard: {err}")
    logger.info("clipboard write: %d chars", len(text))
    return ToolResult(
        content=f"Copied {len(text)} characters. It is ready to paste.",
        data={"chars": len(text)},
    )


async def draft_email(args: dict) -> ToolResult:
    """args: {to?, subject, instructions}. Open a composer with the mail in it.

    The body is written by the harness from short instructions, the same rule
    write_file follows: a document does not travel through tool-call JSON.
    Nothing is sent. The operator reads it, changes it, and presses send, or
    does not.
    """
    to = str((args or {}).get("to") or "").strip()
    subject = str((args or {}).get("subject") or "").strip()
    instructions = str((args or {}).get("instructions") or "").strip()
    if not subject and not instructions:
        return ToolResult.error("A draft needs at least a subject or what to say.")
    if not instructions:
        instructions = f"A short email about: {subject}"

    try:
        from .files import _generate_draft_body

        body = await _generate_draft_body("", instructions, ".txt")
    except Exception as exc:  # noqa: BLE001
        logger.warning("draft_email generate failed: %s", exc)
        return ToolResult.error(f"I could not write that draft: {exc}")
    body = body[:_MAIL_BODY_MAX]

    query = urllib.parse.urlencode(
        {"subject": subject or "(no subject)", "body": body}, quote_via=urllib.parse.quote
    )
    mailto = f"mailto:{urllib.parse.quote(to)}?{query}"
    ok, err = _os_open(mailto)
    if not ok:
        return ToolResult.error(
            "I wrote the draft but could not open a mail composer here "
            f"({err}). Offer to put it on the clipboard instead."
        )
    logger.info("draft_email opened composer to=%r subject=%r", to, subject[:40])
    return ToolResult(
        content=(
            f"Draft opened in their mail client{f' to {to}' if to else ''}"
            f"{f', subject: {subject}' if subject else ''}.\n"
            "Say it is waiting for them to read and send. It has NOT been sent."
        ),
        data={"to": to, "subject": subject, "chars": len(body)},
    )


def open_path(args: dict) -> ToolResult:
    """args: {path: str}. Show the operator a file or folder on their screen."""
    raw = str((args or {}).get("path") or "").strip()
    if not raw:
        return ToolResult.error("open_path needs a path.")

    from .files import _display_path, _load_roots, _to_posix_path, _under_root

    try:
        target = _to_posix_path(raw).resolve()
    except Exception as exc:  # noqa: BLE001
        return ToolResult.error(f"Could not resolve that path: {exc}")
    if not target.exists():
        return ToolResult.error(f"There is nothing at {_display_path(target)}.")
    # Opening is a read of the same kind list_dir does, so it honours the same
    # allow-list. A house that can be talked into opening anything on the disk
    # is a house with no allow-list.
    if _under_root(target if target.is_dir() else target.parent, _load_roots()) is None:
        return ToolResult.error(
            f"{_display_path(target)} is outside the folders this house may touch. "
            "Ask them to add it, or read something under an allowed folder."
        )

    ok, err = _os_open(str(target))
    if not ok:
        return ToolResult.error(f"I could not open that here: {err}")
    logger.info("open_path %s", target)
    return ToolResult(
        content=f"Opened {_display_path(target)} on their screen.",
        data={"path": _display_path(target)},
    )
