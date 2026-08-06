"""consult_claude / claude_status: delegate a task to the Claude Code CLI.

The second consultation seam, shaped like ``consult_liara``: ask a specialist,
fold a structured answer back into the turn. Mentat is the in-house executor
(Ornith, one-file beats against an allow-listed plan); Claude Code is the
frontier agent for work Mentat is not sized for.

ASYNC, NOT BLOCKING. The first live test measured a 62.9s tool round trip and
a 67s turn. Fine at a desk, wrong on an Echo where the operator is standing in
a kitchen waiting for a voice. So this follows the ``mentat_run`` shape: the
work runs in a DAEMON THREAD, the tool returns "started" immediately, progress
is pull-based through ``claude_status``, and terminal states push an operator
notification. Run records survive a gateway restart because the worker writes
them to disk.

WHY A SUBPROCESS AND NOT THE AGENT SDK. The Python and TypeScript Agent SDKs
wrap this same binary rather than replacing it, and neither a node runtime nor
a `claude` install exists inside WSL where Valar runs. The CLI is on the
WINDOWS side, so we cross the boundary the same way the Mentat conductor
already shells to cmd.exe for npm. The tiebreaker will be the approval loop:
Claude comes back needing permission to run what it wrote, and resuming with a
grant is where the SDK earns its keep.

DO NOT ADD --bare. It looks like the right flag for a delegated task and it
breaks authentication: its own help says "Anthropic auth is strictly
ANTHROPIC_API_KEY or apiKeyHelper via --settings (OAuth and keychain are never
read)". Valar authenticates as the operator's logged-in Claude, so --bare
makes every call return "the session requires a login" (live-hit 2026-08-03).
Use --setting-sources and --strict-mcp-config instead: they skip hooks,
plugins, and the machine's dozen MCP servers while leaving OAuth alone.
Measured on the same trivial prompt: plain $0.31 / 29.5k cache-creation
tokens, narrowed $0.135 / 12.5k, and the narrowed call still authenticates.

GROUNDING. The model never supplies a filesystem path. It picks a workspace BY
NAME from the operator-curated allow-list below, the same
config-not-model-trust pattern as mentat_runs.yaml and Wright's GPS.
"""

from __future__ import annotations

import json
import logging
import os
import queue
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.claude_code")

_REPO_ROOT = Path(__file__).resolve().parents[4]

# Workspaces the model may name. Values are resolved server-side.
_WORKSPACES: dict[str, Path] = {
    "scratch": _REPO_ROOT / "sessions" / "claude-scratch",
    "valinor": _REPO_ROOT,
}
_DEFAULT_WORKSPACE = "scratch"

_ALLOWED_MODES = {"acceptEdits", "plan", "dontAsk"}
_DEFAULT_MODE = "acceptEdits"

# What the agent may RUN, per workspace. acceptEdits lets it write a file but
# not execute one, and a capable agent will not accept that quietly: measured
# 2026-08-03, it wrote the script in two steps then burned five minutes
# retrying PowerShell and Bash to verify its own work, refused every time.
# Letting it run what it just wrote, inside a sandbox directory, is both
# faster and more honest than watching it thrash. The live repo grants
# nothing: there, verification stays with the operator.
# NOTE the PowerShell mirror. The CLI is a WINDOWS binary, so the agent
# reaches for the PowerShell tool as readily as Bash, and a Bash-only grant
# leaves it refused on every other attempt (live-hit 2026-08-03: three
# PowerShell refusals in a row while the Bash grant was working fine).
_VERIFY_VERBS = ("python", "python3", "pytest", "ls", "cat", "head", "tail",
                 "printf", "echo", "mkdir", "touch", "dir", "type")
_ALLOWED_TOOLS: dict[str, str] = {
    "scratch": " ".join(
        f"{tool}({verb} *)" for tool in ("Bash", "PowerShell") for verb in _VERIFY_VERBS
    ),
    "valinor": "",
}

_RUNS_DIR = _REPO_ROOT / "sessions" / ".claude-runs"
# Deliberately short. A delegated agent that has not finished in five
# minutes is usually stuck on something it is not allowed to do, and the
# useful move is to SURFACE that (steps so far, commands it wanted, an
# Approve button) rather than hold the operator in a silent wait.
_TIMEOUT_S = int(os.environ.get("VALAR_CLAUDE_TIMEOUT_S", "300"))
_MAX_BODY = 6000

# Single-flight: one delegated agent at a time. Two frontier runs against the
# same repo would race each other's edits.
_active: dict = {"id": None, "thread": None, "started": 0.0}


def _binary() -> str | None:
    """The CLI. Env override first, then the Windows install as seen from WSL,
    then whatever is on PATH (a native Linux install, if one ever lands)."""
    override = os.environ.get("VALAR_CLAUDE_BIN", "").strip()
    if override:
        return override if Path(override).exists() else None
    for candidate in Path("/mnt/c/Users").glob("*/.local/bin/claude.exe"):
        return str(candidate)
    return shutil.which("claude")


def _notify_operator(text: str) -> None:
    """Terminal states only. Same seam as the Mentat conductor."""
    token = os.environ.get("VALAR_NOTIFY_TG_TOKEN", "").strip()
    chat = os.environ.get("VALAR_NOTIFY_TG_CHAT", "").strip()
    if not token or not chat:
        logger.info("operator notify (no telegram env): %s", text)
        return
    try:
        import httpx

        httpx.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat, "text": text},
            timeout=10.0,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("operator notify failed: %s", exc)


def _write_record(record: dict) -> None:
    try:
        _RUNS_DIR.mkdir(parents=True, exist_ok=True)
        (_RUNS_DIR / f"{record['id']}.json").write_text(
            json.dumps(record, indent=2), encoding="utf-8"
        )
    except OSError as exc:
        logger.warning("claude run-record write failed: %s", exc)


def _latest_record() -> dict | None:
    """The active run from memory, else the newest record on disk. A gateway
    restart wipes _active; the records survive."""
    rid = _active.get("id")
    if rid:
        try:
            return json.loads((_RUNS_DIR / f"{rid}.json").read_text(encoding="utf-8"))
        except OSError:
            pass
    try:
        files = sorted(_RUNS_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime)
    except OSError:
        return None
    if not files:
        return None
    try:
        return json.loads(files[-1].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


_FENCE_RE = re.compile(r"```[a-zA-Z]*\n(.*?)```", re.S)

_REFUSAL_RE = re.compile(
    r"permission|not allowed|requires approval|denied|blocked by", re.I
)


def _is_refusal(block: dict) -> bool:
    """A permission refusal, not merely a command that failed. A failing test
    is useful work; a refusal is the agent hitting a wall it cannot pass, and
    it will keep hammering that wall until something stops it."""
    if not block.get("is_error"):
        return False
    content = block.get("content")
    if isinstance(content, list):
        text = " ".join(str(c.get("text", "")) for c in content if isinstance(c, dict))
    else:
        text = str(content or "")
    return bool(_REFUSAL_RE.search(text))



def _pending_commands(body: str) -> list[str]:
    """Commands the agent said it still needs approved. Under acceptEdits it
    can write a file but not run it, so a real task ends with "approve these
    and I'll verify". Surfacing them is what makes the approval loop
    possible (live-hit 2026-08-03)."""
    if not re.search(r"appro|permission|blocked|needs? your", body, re.I):
        return []
    out: list[str] = []
    for block in _FENCE_RE.findall(body):
        for line in block.splitlines():
            line = line.split("#")[0].strip()
            if line and not line.startswith(("$", ">")):
                out.append(line)
    return out[:8]


def _step_from_tool_use(block: dict) -> str | None:
    """One readable line for a tool the agent used. This is the transcript the
    operator wants: not the tokens, what it DID."""
    name = block.get("name") or ""
    inp = block.get("input") or {}
    if name in ("Read", "Write", "Edit", "NotebookEdit"):
        raw = str(inp.get("file_path") or inp.get("path") or "")
        target = raw.replace("\\", "/").rstrip("/").split("/")[-1]
        return f"{name} {target}".strip()
    if name == "Bash":
        cmd = str(inp.get("command") or "").strip()
        return f"Bash {cmd[:90]}"
    if name in ("Glob", "Grep"):
        return f"{name} {str(inp.get('pattern') or '')[:60]}"
    if name == "TodoWrite":
        return None
    return name or None


def _run_claude(
    record: dict,
    task: str,
    workspace: Path,
    mode: str,
    binary: str,
    resume_sid: str = "",
    extra_tools: str = "",
) -> None:
    """The background worker.

    Streams rather than waiting for one JSON blob, so the card can show what
    the agent is doing while it does it. The operator should not have to ask
    "is it done yet" (Joshua, 2026-08-03); the card answers by updating.

    stream-json needs --verbose. Token deltas (--include-partial-messages) are
    deliberately NOT requested: a half-written sentence is not progress, and
    the step list is. Event shapes: code.claude.com/docs/en/headless, where
    system/init comes first, then assistant and user messages carrying
    tool_use and tool_result blocks, then a final result message.
    """
    cmd = [
        binary,
        "-p",
        task,
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        mode,
        # Skip the operator's own hooks, plugins, and settings layers: a
        # delegated task should carry the prompt we wrote, not this machine's
        # developer setup. See the --bare warning above.
        "--setting-sources",
        "",
        # Do not inherit the dozen MCP servers configured for other agents.
        # The house grants its own capability; it does not borrow.
        "--strict-mcp-config",
    ]
    grant = " ".join(
        x for x in (_ALLOWED_TOOLS.get(record["workspace_name"], ""), extra_tools) if x
    )
    if grant:
        cmd += ["--allowedTools", grant]
    if resume_sid:
        cmd += ["--resume", resume_sid]
    model = os.environ.get("VALAR_CLAUDE_MODEL", "").strip()
    if model:
        cmd += ["--model", model]

    steps: list[str] = record.setdefault("steps", [])
    live = []
    hit_refusal = False
    final: dict | None = None
    last_write = 0.0
    deadline = time.time() + _TIMEOUT_S

    def flush(force: bool = False) -> None:
        """Throttled: a token-delta stream would otherwise rewrite the record
        hundreds of times a second for no benefit."""
        nonlocal last_write
        now = time.time()
        if not force and now - last_write < 0.6:
            return
        last_write = now
        record["body"] = "".join(live)[-_MAX_BODY:]
        record["steps"] = steps[-40:]
        _write_record(record)

    # stderr goes to a FILE, never to a pipe we do not drain. An undrained
    # 64KB stderr pipe blocks the child mid-run, which looks exactly like a
    # hung agent (live-hit 2026-08-03).
    err_path = _RUNS_DIR / f"{record['id']}.stderr.log"
    try:
        _RUNS_DIR.mkdir(parents=True, exist_ok=True)
        err_file = open(err_path, "w", encoding="utf-8")
    except OSError:
        err_file = subprocess.DEVNULL

    try:
        proc = subprocess.Popen(  # noqa: S603 - allow-listed binary, no shell
            cmd,
            cwd=str(workspace),
            stdout=subprocess.PIPE,
            stderr=err_file,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except OSError as exc:
        record.update(status="error", finished=time.time(), body=f"Could not start Claude Code: {exc}")
        _write_record(record)
        _active["id"] = None
        return

    # The WSL-to-Windows interop pipe does not reliably close when the child
    # exits, so a plain `for line in proc.stdout` blocks forever on a finished
    # run. Pump it from a daemon thread and read with a timeout instead.
    lines: "queue.Queue[str | None]" = queue.Queue()

    def _pump() -> None:
        try:
            for raw in proc.stdout or []:
                lines.put(raw)
        except Exception:  # noqa: BLE001 - the pipe died; treat as EOF
            pass
        finally:
            lines.put(None)

    threading.Thread(target=_pump, daemon=True).start()

    try:
        while True:
            if time.time() > deadline:
                proc.kill()
                raise subprocess.TimeoutExpired(cmd, _TIMEOUT_S)
            try:
                line = lines.get(timeout=5)
            except queue.Empty:
                # Nothing for 5s. If the process is gone, the run is over and
                # the pipe is simply never going to close.
                if proc.poll() is not None:
                    break
                continue
            if line is None:
                break
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = ev.get("type")

            if kind == "system" and ev.get("subtype") == "init":
                record["model"] = ev.get("model")
                record["session_id"] = ev.get("session_id")
                steps.append("session started")
                flush(force=True)

            elif kind == "assistant":
                # A fresh assistant message means the previous text block is
                # settled; tool_use blocks are the interesting part.
                for block in ((ev.get("message") or {}).get("content") or []):
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        step = _step_from_tool_use(block)
                        if step:
                            steps.append(step)
                            flush(force=True)

            elif kind == "user":
                for block in ((ev.get("message") or {}).get("content") or []):
                    if not isinstance(block, dict) or block.get("type") != "tool_result":
                        continue
                    if not _is_refusal(block):
                        continue
                    # STOP THE RUN. Left alone the agent retries the same
                    # refused action for minutes, on every shell it can think
                    # of, and the operator watches a spinner. End it here and
                    # hand them the decision instead (Joshua, 2026-08-03).
                    if steps:
                        steps[-1] = steps[-1] + "  (refused)"
                    hit_refusal = True
                    flush(force=True)
                    try:
                        proc.kill()
                    except OSError:
                        pass
                    break
                if hit_refusal:
                    break

            elif kind == "result":
                # STOP HERE. Do not wait for stdout to EOF: the run's own
                # process exits, but the WSL-to-Windows interop pipe does not
                # reliably close behind it, so the reader blocks forever and
                # the record stays "running" with a complete transcript in it
                # (live-hit 2026-08-03). The result event is the terminal
                # signal; take it and go.
                final = ev
                break

        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except OSError:
            pass
        partial = "".join(live).strip()
        refused = [st for st in steps if "(refused)" in st]
        note = f"I stopped waiting after {_TIMEOUT_S // 60} minutes."
        if refused:
            note += (
                f" It spent that time retrying {len(refused)} action(s) it is not"
                " allowed to take. Approve them below and it can pick up where it"
                " left off."
            )
        record.update(
            status="timeout",
            finished=time.time(),
            body=(partial + chr(10) + chr(10) + note).strip() if partial else note,
            steps=steps[-40:],
            pending=[st.split(" ", 1)[-1].replace("  (refused)", "").strip()
                     for st in refused][:8],
        )
        flush(force=True)
        _notify_operator(f"Claude Code stalled on: {record['task'][:120]}")
        _active["id"] = None
        return
    except Exception as exc:  # noqa: BLE001
        record.update(status="error", finished=time.time(), body=str(exc)[:_MAX_BODY])
        flush(force=True)
        _notify_operator(f"Claude Code failed: {str(exc)[:160]}")
        _active["id"] = None
        return

    if hit_refusal:
        blocked = [
            st.split(" ", 1)[-1].replace("  (refused)", "").strip()
            for st in steps
            if "(refused)" in st
        ]
        record.update(
            status="blocked",
            finished=time.time(),
            body=(
                "I stopped because it needs your permission to go further. "
                "Everything it did up to that point is in the steps above."
            ),
            steps=steps[-40:],
            pending=blocked[:8],
        )
        flush(force=True)
        _notify_operator(f"Claude Code needs approval: {record['task'][:100]}")
        _active["id"] = None
        return

    if final is None:
        # No result event, but the transcript and the streamed text are real.
        # Report what we saw rather than throwing the run away.
        streamed = "".join(live).strip()
        err = ""
        try:
            err = err_path.read_text(encoding="utf-8", errors="replace").strip()[-400:]
        except OSError:
            pass
        record.update(
            status="done" if streamed else "error",
            finished=time.time(),
            body=streamed or err or "Claude Code ended without a result.",
            pending=_pending_commands(streamed),
            steps=steps[-40:],
        )
        flush(force=True)
        _active["id"] = None
        return

    payload = final
    body = str(payload.get("result") or "").strip()[:_MAX_BODY] or "".join(live)[-_MAX_BODY:]
    record.update(
        status="error" if payload.get("is_error") else "done",
        finished=time.time(),
        body=body,
        session_id=payload.get("session_id") or record.get("session_id"),
        cost_usd=payload.get("total_cost_usd"),
        num_turns=payload.get("num_turns"),
        denials=len(payload.get("permission_denials") or []),
        pending=_pending_commands(body),
        steps=steps[-40:],
    )
def _card(record: dict) -> dict:
    """The terminal card. One shape for every delegated agent and third-party
    tool, so a future integration renders correctly without a new card type."""
    status = record.get("status", "running")
    meta = []
    if record.get("num_turns"):
        meta.append(f"{record['num_turns']} turns")
    if isinstance(record.get("cost_usd"), (int, float)):
        meta.append(f"${record['cost_usd']:.2f}")
    if record.get("finished"):
        meta.append(f"{int(record['finished'] - record['started'])}s")
    return {
        "version": 1,
        "type": "terminal_card",
        "props": {
            "title": "Claude Code",
            "subtitle": f"{record['workspace_name']} workspace",
            "status": status,
            "body": record.get("body", ""),
            "meta": meta,
            "pending": record.get("pending") or [],
            "steps": record.get("steps") or [],
            # The client polls /claude/state while status is running, so the
            # card fills in on its own instead of waiting to be asked.
            "run_id": record.get("id"),
        },
    }


async def consult_claude(args: dict) -> ToolResult:
    task = str(args.get("task") or "").strip()
    if not task:
        return ToolResult.error("consult_claude needs a task to hand over.")

    ws_name = str(args.get("workspace") or _DEFAULT_WORKSPACE).strip().lower()
    workspace = _WORKSPACES.get(ws_name)
    if workspace is None:
        allowed = ", ".join(sorted(_WORKSPACES))
        return ToolResult.error(
            f"'{ws_name}' is not a workspace Claude may work in. Allowed: {allowed}."
        )

    mode = str(args.get("mode") or _DEFAULT_MODE).strip()
    if mode not in _ALLOWED_MODES:
        mode = _DEFAULT_MODE

    thread = _active.get("thread")
    if thread is not None and thread.is_alive():
        return ToolResult(
            content="Claude is already working on something. Ask me for the status, "
            "or wait for it to finish before handing over another task.",
        )

    binary = _binary()
    if not binary:
        return ToolResult.error(
            "The Claude Code CLI is not installed where Valar can reach it."
        )
    try:
        workspace.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return ToolResult.error(f"Could not open the {ws_name} workspace: {exc}")

    record = {
        "id": f"{int(time.time())}-{ws_name}",
        "task": task,
        "workspace_name": ws_name,
        "workspace": str(workspace),
        "mode": mode,
        "status": "running",
        "started": time.time(),
        "body": "",
    }
    _write_record(record)

    worker = threading.Thread(
        target=_run_claude, args=(record, task, workspace, mode, binary), daemon=True
    )
    _active.update(id=record["id"], thread=worker, started=record["started"])
    worker.start()
    logger.info("consult_claude started id=%s workspace=%s mode=%s", record["id"], ws_name, mode)

    return ToolResult(
        content=(
            f"Claude Code has started on it, in the {ws_name} workspace. This usually takes "
            "about a minute. Tell the operator it is underway and that you will report back; "
            "they can ask for the status any time."
        ),
        data={"run_id": record["id"], "ui_component": _card(record)},
    )


async def claude_status(args: dict) -> ToolResult:
    """What Claude is doing, or what it reported when it last finished."""
    record = _latest_record()
    if record is None:
        return ToolResult(content="Claude Code has not been asked for anything yet.")

    status = record.get("status", "running")
    if status == "running":
        elapsed = int(time.time() - record["started"])
        return ToolResult(
            content=f"Claude is still working, {elapsed}s in, on: {record['task'][:200]}",
            data={"ui_component": _card(record)},
        )

    body = record.get("body", "")
    pending = record.get("pending") or []
    lead = f"Claude finished. It reported:\n\n{body}"
    if pending:
        lead += (
            "\n\nIt could not run these itself and needs the operator's approval:\n"
            + "\n".join(f"  {c}" for c in pending)
        )
    return ToolResult(content=lead, ok=status != "error", data={"ui_component": _card(record)})


def latest_state() -> dict:
    """The current (or last) run, for the read-only HTTP route the clients
    poll. Same shape as the card props, plus the task."""
    record = _latest_record()
    if record is None:
        return {"run": None, "status": "none"}
    return {
        "run": record.get("id"),
        "status": record.get("status", "running"),
        "task": record.get("task", ""),
        "workspace": record.get("workspace_name", ""),
        "body": record.get("body", ""),
        "steps": record.get("steps") or [],
        "pending": record.get("pending") or [],
        "started": record.get("started"),
        "finished": record.get("finished"),
        "cost_usd": record.get("cost_usd"),
        "num_turns": record.get("num_turns"),
        "model": record.get("model"),
    }


def _grant_for(commands: list[str]) -> str:
    """Turn the commands the agent asked to run into the narrowest allow-list
    that covers them. `python check.py x` becomes `Bash(python *)`, not a
    blanket Bash grant, so approving one verification does not hand over the
    shell."""
    tools = set()
    for c in commands:
        parts = c.strip().split()
        if parts:
            tools.add(f"Bash({parts[0]} *)")
            tools.add(f"PowerShell({parts[0]} *)")
    return " ".join(sorted(tools))


def decide(run_id: str, approve: bool) -> dict:
    """The operator's answer to a permission request, from the card's Approve
    or Deny button. Approving resumes the SAME Claude session with a grant
    scoped to what it asked for, so it can verify the work it already did
    instead of starting over."""
    record = _latest_record()
    if record is None or record.get("id") != run_id:
        return {"ok": False, "error": "That run is no longer the current one."}
    pending = record.get("pending") or []
    if not pending:
        return {"ok": False, "error": "Nothing is waiting on a decision."}

    if not approve:
        record.update(pending=[], decision="denied")
        _write_record(record)
        return {"ok": True, "status": record.get("status"), "decision": "denied"}

    sid = record.get("session_id") or ""
    binary = _binary()
    if not sid or not binary:
        return {"ok": False, "error": "That session can no longer be resumed."}

    thread = _active.get("thread")
    if thread is not None and thread.is_alive():
        return {"ok": False, "error": "Claude is busy with another run."}

    grant = _grant_for(pending)
    record.update(
        status="running",
        decision="approved",
        pending=[],
        finished=None,
        started=time.time(),
        steps=(record.get("steps") or []) + ["approved: " + grant],
    )
    _write_record(record)

    worker = threading.Thread(
        target=_run_claude,
        args=(
            record,
            "Run the commands you said you needed approved, then report what "
            "actually happened. Do not start over.",
            Path(record["workspace"]),
            record.get("mode", _DEFAULT_MODE),
            binary,
            sid,
            grant,
        ),
        daemon=True,
    )
    _active.update(id=record["id"], thread=worker, started=record["started"])
    worker.start()
    logger.info("claude approval granted id=%s grant=%s", run_id, grant)
    return {"ok": True, "status": "running", "decision": "approved", "grant": grant}
