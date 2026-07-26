from __future__ import annotations

from typing import Any, Callable

from mcp.server.fastmcp import FastMCP, Image

from .config import BridgeSettings
from .runtime import DesktopBridge, json_error, json_result

settings = BridgeSettings()
bridge = DesktopBridge(settings)
mcp = FastMCP(
    "Desktop MCP Bridge",
    instructions=(
        "A full-capability Windows desktop and browser bridge. Observe before acting. Prefer "
        "structured filesystem, Playwright, process, UI Automation, OCR, and job tools over pixel "
        "clicks. Verify outcomes. The local kill switch overrides all mutating actions."
    ),
    host=settings.host,
    port=settings.port,
)

READ_ONLY = {"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False}
MUTATING_LOCAL = {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False}
MUTATING_OPEN = {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True}


def _json_call(callback: Callable[[], Any]) -> str:
    try:
        return json_result(callback())
    except Exception as exc:
        return json_error(exc)


@mcp.tool(annotations=READ_ONLY)
def bridge_status() -> str:
    """Return profile, capabilities, admin state, roots, audit path, and kill-switch state."""
    return _json_call(bridge.status)


@mcp.tool(annotations=READ_ONLY)
def system_info() -> str:
    """Return OS, CPU, memory, disk, hostname, and network-interface information."""
    return _json_call(bridge.system_info)


@mcp.tool(annotations=READ_ONLY)
def observe_desktop(
    monitor: int = 1, max_width: int = 1920, image_format: str = "png"
) -> Image:
    """Capture a monitor as PNG/JPEG. Monitor 0 captures the full virtual desktop."""
    data, metadata = bridge.observe_desktop_bytes(
        monitor=monitor,
        max_width=max_width,
        image_format=image_format,
        source="mcp",
    )
    return Image(data=data, format=metadata["extension"])


@mcp.tool(annotations=READ_ONLY)
def capture_desktop_artifact(
    monitor: int = 1,
    max_width: int = 1920,
    image_format: str = "png",
    ttl_seconds: int | None = None,
) -> str:
    """Capture the desktop into a signed short-lived artifact."""
    return _json_call(
        lambda: bridge.capture_desktop_artifact(
            monitor, max_width, image_format, ttl_seconds, source="mcp"
        )
    )


@mcp.tool(annotations=READ_ONLY)
def screen_ocr(
    monitor: int = 1,
    language: str = "eng",
    min_confidence: float = 35.0,
    include_image: bool = True,
    max_width: int = 2560,
) -> str:
    """Run local Tesseract OCR over a desktop capture and return text with bounding boxes."""
    return _json_call(
        lambda: bridge.screen_ocr(
            monitor,
            language,
            min_confidence,
            include_image,
            max_width,
            source="mcp",
        )
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def desktop_step(actions: list[dict[str, Any]], return_screenshot: bool = True) -> list[Any]:
    """Execute batched mouse, keyboard, scroll, drag, keypress, and wait actions."""
    try:
        result = bridge.desktop_step(actions, return_screenshot=False, source="mcp")
        rows: list[Any] = [json_result(result)]
        if return_screenshot:
            data, metadata = bridge.observe_desktop_bytes(source="mcp")
            rows.append(Image(data=data, format=metadata["extension"]))
        return rows
    except Exception as exc:
        return [json_error(exc)]


@mcp.tool(annotations=READ_ONLY)
def list_directory(path: str = ".", recursive: bool = False, limit: int = 500) -> str:
    """List a directory. Full profile can access any path visible to the Windows account."""
    return _json_call(lambda: bridge.list_directory(path, recursive, limit, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def read_text_file(
    path: str,
    start_line: int = 1,
    end_line: int | None = None,
    encoding: str = "utf-8",
) -> str:
    """Read a bounded text file with optional line slicing and encoding selection."""
    return _json_call(
        lambda: bridge.read_text_file(path, start_line, end_line, encoding, source="mcp")
    )


@mcp.tool(annotations=READ_ONLY)
def read_binary_file(path: str, offset: int = 0, length: int | None = None) -> str:
    """Read a bounded binary range and return Base64 content."""
    return _json_call(lambda: bridge.read_binary_file(path, offset, length, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def write_text_file(
    path: str,
    content: str,
    overwrite: bool = False,
    create_parents: bool = False,
    encoding: str = "utf-8",
) -> str:
    """Create or replace a text file."""
    return _json_call(
        lambda: bridge.write_text_file(
            path, content, overwrite, create_parents, encoding, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def write_binary_file(
    path: str,
    content_base64: str,
    overwrite: bool = False,
    create_parents: bool = False,
) -> str:
    """Create or replace a binary file from Base64 content."""
    return _json_call(
        lambda: bridge.write_binary_file(
            path, content_base64, overwrite, create_parents, source="mcp"
        )
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": False, "openWorldHint": False})
def copy_path(source_path: str, destination_path: str, overwrite: bool = False) -> str:
    """Copy a file or directory."""
    return _json_call(
        lambda: bridge.copy_path(source_path, destination_path, overwrite, source="mcp")
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def move_path(source_path: str, destination_path: str, overwrite: bool = False) -> str:
    """Move or rename a file or directory."""
    return _json_call(
        lambda: bridge.move_path(source_path, destination_path, overwrite, source="mcp")
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def delete_path(path: str, recursive: bool = False) -> str:
    """Delete a file or directory. Recursive deletion requires full profile."""
    return _json_call(lambda: bridge.delete_path(path, recursive, source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def run_command(
    command: str,
    cwd: str | None = None,
    timeout_seconds: int | None = None,
    environment: dict[str, str] | None = None,
) -> str:
    """Run a synchronous command. Full profile permits arbitrary commands and paths."""
    return _json_call(
        lambda: bridge.run_command(
            command, cwd, timeout_seconds, environment, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_OPEN)
def start_command_job(
    command: str,
    cwd: str | None = None,
    environment: dict[str, str] | None = None,
) -> str:
    """Start a long-running command and return a job ID immediately."""
    return _json_call(
        lambda: bridge.start_command_job(command, cwd, environment, source="mcp")
    )


@mcp.tool(annotations=READ_ONLY)
def get_command_job(job_id: str, tail_bytes: int = 100_000) -> str:
    """Get job state and bounded stdout/stderr tails."""
    return _json_call(lambda: bridge.get_command_job(job_id, tail_bytes, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def list_command_jobs(limit: int = 100) -> str:
    """List known long-running command jobs."""
    return _json_call(lambda: bridge.list_command_jobs(limit, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def cancel_command_job(job_id: str, force: bool = False) -> str:
    """Cancel a long-running command job, optionally killing its process tree."""
    return _json_call(lambda: bridge.cancel_command_job(job_id, force, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def list_processes(limit: int = 500, include_command_line: bool = False) -> str:
    """List processes. Command lines require full profile because they may contain secrets."""
    return _json_call(
        lambda: bridge.list_processes(limit, include_command_line, source="mcp")
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def stop_process(pid: int, force: bool = False, tree: bool = False) -> str:
    """Terminate or kill a process, optionally including descendants."""
    return _json_call(lambda: bridge.stop_process(pid, force, tree, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def clipboard_read() -> str:
    """Read text from the Windows clipboard."""
    return _json_call(lambda: bridge.clipboard_read(source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def clipboard_write(text: str) -> str:
    """Replace clipboard text."""
    return _json_call(lambda: bridge.clipboard_write(text, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def list_windows() -> str:
    """List titled top-level Windows windows and their geometry/state."""
    return _json_call(lambda: bridge.list_windows(source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def window_control(title: str, operation: str) -> str:
    """Activate, minimize, maximize, restore, or close the first matching window."""
    return _json_call(lambda: bridge.window_control(title, operation, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def uia_tree(title_re: str = ".*", depth: int = 4, max_elements: int = 500) -> str:
    """Inspect a Windows UI Automation tree with names, types, IDs, and rectangles."""
    return _json_call(lambda: bridge.uia_tree(title_re, depth, max_elements, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def uia_invoke(
    title_re: str,
    selector: dict[str, Any],
    action: str = "click",
    value: str | None = None,
) -> str:
    """Interact with a UI element by semantic selector instead of coordinates."""
    return _json_call(
        lambda: bridge.uia_invoke(title_re, selector, action, value, source="mcp")
    )


@mcp.tool(annotations=READ_ONLY)
def browser_status() -> str:
    """Return managed Playwright browser state and paths."""
    return _json_call(lambda: bridge.browser_status(source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def browser_start(headless: bool | None = None) -> str:
    """Start the managed persistent Chromium session."""
    return _json_call(lambda: bridge.browser_start(headless, source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def browser_navigate(
    url: str, wait_until: str = "domcontentloaded", timeout_seconds: int = 30
) -> str:
    """Navigate the active managed browser tab."""
    return _json_call(
        lambda: bridge.browser_navigate(url, wait_until, timeout_seconds, source="mcp")
    )


@mcp.tool(annotations=READ_ONLY)
def browser_snapshot(max_chars: int = 60_000) -> str:
    """Return page title/URL, ARIA snapshot, visible controls, console, and page errors."""
    return _json_call(lambda: bridge.browser_snapshot(max_chars, source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def browser_interact(
    action: str,
    selector: dict[str, Any],
    value: Any = None,
    timeout_seconds: int = 30,
) -> str:
    """Click/fill/type/press/check/select/hover using a semantic browser locator."""
    return _json_call(
        lambda: bridge.browser_interact(
            action, selector, value, timeout_seconds, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_OPEN)
def browser_tabs(
    tab_operation: str, index: int | None = None, url: str | None = None
) -> str:
    """List, create, switch, or close managed browser tabs."""
    return _json_call(
        lambda: bridge.browser_tabs(tab_operation, index, url, source="mcp")
    )


@mcp.tool(annotations=READ_ONLY)
def browser_screenshot(
    full_page: bool = True,
    image_format: str = "png",
    quality: int = 85,
    ttl_seconds: int | None = None,
) -> str:
    """Capture the current browser page into a signed short-lived artifact."""
    return _json_call(
        lambda: bridge.browser_screenshot(
            full_page, image_format, quality, ttl_seconds, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_OPEN)
def browser_upload(selector: dict[str, Any], path: str) -> str:
    """Upload a local file through a browser file input."""
    return _json_call(lambda: bridge.browser_upload(selector, path, source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def browser_download(
    selector: dict[str, Any], destination: str, timeout_seconds: int = 30
) -> str:
    """Click a browser control and save the resulting download."""
    return _json_call(
        lambda: bridge.browser_download(
            selector, destination, timeout_seconds, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_OPEN)
def browser_evaluate(expression: str) -> str:
    """Evaluate JavaScript in the page. Full profile only."""
    return _json_call(lambda: bridge.browser_evaluate(expression, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def browser_close() -> str:
    """Close the managed browser context."""
    return _json_call(lambda: bridge.browser_close(source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def registry_get(hive: str, key: str, value_name: str = "") -> str:
    """Read a Windows registry value. Enabled in full profile."""
    return _json_call(lambda: bridge.registry_get(hive, key, value_name, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def registry_set(
    hive: str,
    key: str,
    value_name: str,
    value: Any,
    value_type: str = "string",
) -> str:
    """Create/update a registry value. Enabled in full profile."""
    return _json_call(
        lambda: bridge.registry_set(hive, key, value_name, value, value_type, source="mcp")
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def registry_delete(hive: str, key: str, value_name: str | None = None) -> str:
    """Delete a registry value or key. Enabled in full profile."""
    return _json_call(lambda: bridge.registry_delete(hive, key, value_name, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def service_control(service_name: str, operation: str) -> str:
    """Query/start/stop/pause/continue/restart a Windows service."""
    return _json_call(lambda: bridge.service_control(service_name, operation, source="mcp"))


@mcp.tool(annotations=MUTATING_OPEN)
def package_manage(
    manager: str,
    operation: str,
    package: str,
    extra_args: list[str] | None = None,
) -> str:
    """Search/install/upgrade/uninstall with winget, Chocolatey, or Scoop."""
    return _json_call(
        lambda: bridge.package_manage(manager, operation, package, extra_args, source="mcp")
    )


@mcp.tool(annotations=MUTATING_OPEN)
def network_admin(operation: str, target: str | None = None) -> str:
    """Inspect networking, flush DNS, ping, or resolve a target."""
    return _json_call(lambda: bridge.network_admin(operation, target, source="mcp"))


@mcp.tool(annotations=MUTATING_LOCAL)
def scheduled_task_control(
    operation: str,
    task_name: str,
    command: str | None = None,
    schedule: str | None = None,
) -> str:
    """Query/run/end/delete/create a Windows scheduled task."""
    return _json_call(
        lambda: bridge.scheduled_task_control(
            operation, task_name, command, schedule, source="mcp"
        )
    )


@mcp.tool(annotations=MUTATING_LOCAL)
def power_control(operation: str, delay_seconds: int = 0) -> str:
    """Shutdown, restart, log off, abort shutdown, lock, or sleep Windows."""
    return _json_call(lambda: bridge.power_control(operation, delay_seconds, source="mcp"))


@mcp.tool(annotations=READ_ONLY)
def audit_tail(limit: int = 100) -> str:
    """Return recent redacted JSONL audit entries."""
    return _json_call(lambda: bridge.audit_tail(limit, source="mcp"))


def run() -> None:
    if settings.transport == "stdio":
        mcp.run(transport="stdio")
    elif settings.transport == "sse":
        mcp.run(transport="sse")
    else:
        mcp.run(transport="streamable-http")
