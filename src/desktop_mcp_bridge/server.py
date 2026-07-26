from __future__ import annotations

import io
import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

import mss
import psutil
import pyautogui
from mcp.server.fastmcp import FastMCP, Image
from PIL import Image as PILImage

from .config import BridgeSettings, CommandRequest, DesktopAction
from .security import SecurityViolation, resolve_allowed_path, validate_command

settings = BridgeSettings()
mcp = FastMCP(
    "Desktop MCP Bridge",
    instructions=(
        "A permission-aware bridge to the user's Windows desktop. Prefer filesystem and shell tools "
        "over visual interaction. Observe before clicking. Never claim success without verifying."
    ),
    host=settings.host,
    port=settings.port,
)


def _ok(**payload: Any) -> str:
    return json.dumps({"ok": True, **payload}, ensure_ascii=False, default=str)


def _error(exc: Exception) -> str:
    return json.dumps(
        {"ok": False, "error": type(exc).__name__, "message": str(exc)},
        ensure_ascii=False,
    )


@mcp.tool()
def bridge_status() -> str:
    """Return bridge capabilities, safety settings, and allowed filesystem roots."""
    return _ok(
        version="0.1.0",
        platform=os.name,
        transport=settings.transport,
        desktop_control=settings.enable_desktop_control,
        shell=settings.enable_shell,
        process_control=settings.enable_process_control,
        delete=settings.enable_delete,
        allowed_roots=[str(path) for path in settings.allowed_roots],
        allowed_executables=settings.allowed_executables,
    )


@mcp.tool()
def observe_desktop(monitor: int = 1, max_width: int = 1600) -> Image:
    """Capture one monitor and return a PNG screenshot. Monitor 0 captures the virtual desktop."""
    if not settings.enable_desktop_control:
        raise SecurityViolation("Desktop control is disabled")
    with mss.mss() as capture:
        if monitor < 0 or monitor >= len(capture.monitors):
            raise ValueError(f"Invalid monitor index. Available: 0..{len(capture.monitors) - 1}")
        shot = capture.grab(capture.monitors[monitor])
        image = PILImage.frombytes("RGB", shot.size, shot.rgb)
        if max_width > 0 and image.width > max_width:
            ratio = max_width / image.width
            image = image.resize((max_width, int(image.height * ratio)))
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        return Image(data=buffer.getvalue(), format="png")


@mcp.tool()
def desktop_step(actions: list[dict[str, Any]], return_screenshot: bool = True) -> list[Any]:
    """Execute a bounded batch of mouse/keyboard actions and optionally return a screenshot."""
    if not settings.enable_desktop_control:
        return [_error(SecurityViolation("Desktop control is disabled"))]
    if not 1 <= len(actions) <= 50:
        return [_error(ValueError("actions must contain between 1 and 50 items"))]

    parsed = [DesktopAction.model_validate(action) for action in actions]
    try:
        for action in parsed:
            _perform_action(action)
        result: list[Any] = [_ok(actions_executed=len(parsed), cursor=pyautogui.position())]
        if return_screenshot:
            result.append(observe_desktop())
        return result
    except Exception as exc:  # tool boundary
        return [_error(exc)]


def _perform_action(action: DesktopAction) -> None:
    if action.type in {"click", "double_click", "move", "drag"} and (action.x is None or action.y is None):
        raise ValueError(f"{action.type} requires x and y")
    if action.type == "click":
        pyautogui.click(action.x, action.y, duration=action.duration, button=action.button)
    elif action.type == "double_click":
        pyautogui.doubleClick(action.x, action.y, interval=0.12, duration=action.duration, button=action.button)
    elif action.type == "move":
        pyautogui.moveTo(action.x, action.y, duration=action.duration)
    elif action.type == "drag":
        pyautogui.dragTo(action.x, action.y, duration=action.duration, button=action.button)
    elif action.type == "scroll":
        if action.amount is None:
            raise ValueError("scroll requires amount")
        pyautogui.scroll(action.amount)
    elif action.type == "type":
        if action.text is None:
            raise ValueError("type requires text")
        pyautogui.write(action.text, interval=0.01)
    elif action.type == "hotkey":
        if not action.keys:
            raise ValueError("hotkey requires keys")
        pyautogui.hotkey(*action.keys)
    elif action.type == "wait":
        time.sleep(action.seconds or 0)


@mcp.tool()
def list_directory(path: str = ".", recursive: bool = False, limit: int = 500) -> str:
    """List an allowed directory. Recursive output is capped by limit."""
    try:
        directory = resolve_allowed_path(path, settings, must_exist=True)
        if not directory.is_dir():
            raise NotADirectoryError(directory)
        iterator = directory.rglob("*") if recursive else directory.iterdir()
        entries = []
        for index, item in enumerate(iterator):
            if index >= max(1, min(limit, 5000)):
                break
            stat = item.stat()
            entries.append({
                "path": str(item.relative_to(directory)),
                "type": "directory" if item.is_dir() else "file",
                "size": stat.st_size,
                "modified": stat.st_mtime,
            })
        return _ok(directory=str(directory), entries=entries, count=len(entries))
    except Exception as exc:
        return _error(exc)


@mcp.tool()
def read_text_file(path: str, start_line: int = 1, end_line: int | None = None) -> str:
    """Read a UTF-8 text file inside an allowed root with line slicing and size limits."""
    try:
        file_path = resolve_allowed_path(path, settings, must_exist=True)
        if file_path.stat().st_size > settings.max_read_bytes:
            raise ValueError(f"File exceeds max_read_bytes={settings.max_read_bytes}")
        text = file_path.read_text(encoding="utf-8")
        lines = text.splitlines()
        start = max(1, start_line)
        stop = len(lines) if end_line is None else min(len(lines), max(start, end_line))
        return _ok(path=str(file_path), start_line=start, end_line=stop, content="\n".join(lines[start - 1:stop]))
    except Exception as exc:
        return _error(exc)


@mcp.tool()
def write_text_file(path: str, content: str, overwrite: bool = False, create_parents: bool = False) -> str:
    """Create or replace a UTF-8 text file inside an allowed root."""
    try:
        if len(content.encode("utf-8")) > settings.max_write_bytes:
            raise ValueError(f"Content exceeds max_write_bytes={settings.max_write_bytes}")
        file_path = resolve_allowed_path(path, settings, must_exist=False)
        if file_path.exists() and not overwrite:
            raise FileExistsError("File exists; set overwrite=true to replace it")
        if create_parents:
            file_path.parent.mkdir(parents=True, exist_ok=True)
        elif not file_path.parent.exists():
            raise FileNotFoundError(f"Parent directory does not exist: {file_path.parent}")
        file_path.write_text(content, encoding="utf-8", newline="\n")
        return _ok(path=str(file_path), bytes_written=len(content.encode("utf-8")))
    except Exception as exc:
        return _error(exc)


@mcp.tool()
def delete_path(path: str, recursive: bool = False) -> str:
    """Delete an allowed file or empty directory. Disabled by default."""
    try:
        if not settings.enable_delete:
            raise SecurityViolation("Delete operations are disabled")
        target = resolve_allowed_path(path, settings, must_exist=True)
        if target.is_file() or target.is_symlink():
            target.unlink()
        elif recursive:
            raise SecurityViolation("Recursive directory deletion is intentionally unsupported")
        else:
            target.rmdir()
        return _ok(deleted=str(target))
    except Exception as exc:
        return _error(exc)


@mcp.tool()
def run_command(command: str, cwd: str | None = None, timeout_seconds: int | None = None) -> str:
    """Run an allowlisted command inside an allowed working directory and return captured output."""
    try:
        request = CommandRequest(command=command, cwd=Path(cwd) if cwd else None, timeout_seconds=timeout_seconds)
        validate_command(request.command, settings)
        working_dir = resolve_allowed_path(request.cwd or settings.allowed_roots[0], settings, must_exist=True)
        timeout = request.timeout_seconds or settings.command_timeout_seconds
        completed = subprocess.run(
            request.command,
            cwd=working_dir,
            shell=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        return _ok(
            command=request.command,
            cwd=str(working_dir),
            exit_code=completed.returncode,
            stdout=completed.stdout[-200_000:],
            stderr=completed.stderr[-200_000:],
        )
    except subprocess.TimeoutExpired as exc:
        return _error(TimeoutError(f"Command exceeded timeout: {exc.timeout}s"))
    except Exception as exc:
        return _error(exc)


@mcp.tool()
def list_processes(limit: int = 200) -> str:
    """List running processes without exposing environment variables or command-line secrets."""
    rows = []
    for process in psutil.process_iter(["pid", "name", "username", "status"]):
        try:
            rows.append(process.info)
            if len(rows) >= max(1, min(limit, 1000)):
                break
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return _ok(processes=rows, count=len(rows))


@mcp.tool()
def stop_process(pid: int) -> str:
    """Terminate a process by PID. Disabled by default."""
    try:
        if not settings.enable_process_control:
            raise SecurityViolation("Process control is disabled")
        if pid in {0, 4, os.getpid()}:
            raise SecurityViolation("Protected process")
        process = psutil.Process(pid)
        name = process.name()
        process.terminate()
        process.wait(timeout=10)
        return _ok(pid=pid, name=name, terminated=True)
    except Exception as exc:
        return _error(exc)


def run() -> None:
    if settings.transport == "stdio":
        mcp.run(transport="stdio")
    elif settings.transport == "sse":
        mcp.run(transport="sse")
    else:
        mcp.run(transport="streamable-http")
