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
        "A full-capability Windows desktop bridge. Observe before acting. Prefer structured "
        "filesystem, process, UI Automation, and job tools over pixel clicks. Verify outcomes. "
        "The local kill switch overrides all mutating actions."
    ),
    host=settings.host,
    port=settings.port,
)


def _json_call(callback: Callable[[], Any]) -> str:
    try:
        return json_result(callback())
    except Exception as exc:
        return json_error(exc)


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def bridge_status() -> str:
    """Return access profile, capabilities, admin state, roots, audit path, and kill-switch state."""
    return _json_call(bridge.status)


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def system_info() -> str:
    """Return OS, CPU, memory, disk, hostname, and network-interface information."""
    return _json_call(bridge.system_info)


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def observe_desktop(monitor: int = 1, max_width: int = 1920, image_format: str = "png") -> Image:
    """Capture a monitor as PNG/JPEG. Monitor 0 captures the full virtual desktop."""
    data, metadata = bridge.observe_desktop_bytes(
        monitor=monitor,
        max_width=max_width,
        image_format=image_format,
        source="mcp",
    )
    return Image(data=data, format=metadata["extension"])


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
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


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def list_directory(path: str = ".", recursive: bool = False, limit: int = 500) -> str:
    """List a directory. Full profile can access any path visible to the Windows account."""
    return _json_call(lambda: bridge.list_directory(path, recursive, limit, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
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


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def read_binary_file(path: str, offset: int = 0, length: int | None = None) -> str:
    """Read a bounded binary range and return Base64 content."""
    return _json_call(lambda: bridge.read_binary_file(path, offset, length, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
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
            path,
            content,
            overwrite,
            create_parents,
            encoding,
            source="mcp",
        )
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def write_binary_file(
    path: str,
    content_base64: str,
    overwrite: bool = False,
    create_parents: bool = False,
) -> str:
    """Create or replace a binary file from Base64 content."""
    return _json_call(
        lambda: bridge.write_binary_file(
            path,
            content_base64,
            overwrite,
            create_parents,
            source="mcp",
        )
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": False, "openWorldHint": False})
def copy_path(source_path: str, destination_path: str, overwrite: bool = False) -> str:
    """Copy a file or directory."""
    return _json_call(
        lambda: bridge.copy_path(source_path, destination_path, overwrite, source="mcp")
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def move_path(source_path: str, destination_path: str, overwrite: bool = False) -> str:
    """Move or rename a file or directory."""
    return _json_call(
        lambda: bridge.move_path(source_path, destination_path, overwrite, source="mcp")
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def delete_path(path: str, recursive: bool = False) -> str:
    """Delete a file or directory. Recursive deletion requires full profile."""
    return _json_call(lambda: bridge.delete_path(path, recursive, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True})
def run_command(
    command: str,
    cwd: str | None = None,
    timeout_seconds: int | None = None,
    environment: dict[str, str] | None = None,
) -> str:
    """Run a synchronous command. Full profile permits arbitrary commands and paths."""
    return _json_call(
        lambda: bridge.run_command(
            command,
            cwd,
            timeout_seconds,
            environment,
            source="mcp",
        )
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True})
def start_command_job(
    command: str,
    cwd: str | None = None,
    environment: dict[str, str] | None = None,
) -> str:
    """Start a long-running command and return a job ID immediately."""
    return _json_call(
        lambda: bridge.start_command_job(command, cwd, environment, source="mcp")
    )


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def get_command_job(job_id: str, tail_bytes: int = 100_000) -> str:
    """Get job state and bounded stdout/stderr tails."""
    return _json_call(lambda: bridge.get_command_job(job_id, tail_bytes, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def list_command_jobs(limit: int = 100) -> str:
    """List known long-running command jobs."""
    return _json_call(lambda: bridge.list_command_jobs(limit, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def cancel_command_job(job_id: str, force: bool = False) -> str:
    """Cancel a long-running command job, optionally killing its process tree."""
    return _json_call(lambda: bridge.cancel_command_job(job_id, force, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def list_processes(limit: int = 500, include_command_line: bool = False) -> str:
    """List processes. Command lines require full profile because they may contain secrets."""
    return _json_call(
        lambda: bridge.list_processes(limit, include_command_line, source="mcp")
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def stop_process(pid: int, force: bool = False, tree: bool = False) -> str:
    """Terminate or kill a process, optionally including descendants."""
    return _json_call(lambda: bridge.stop_process(pid, force, tree, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def clipboard_read() -> str:
    """Read text from the Windows clipboard."""
    return _json_call(lambda: bridge.clipboard_read(source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True})
def clipboard_write(text: str) -> str:
    """Replace clipboard text."""
    return _json_call(lambda: bridge.clipboard_write(text, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def list_windows() -> str:
    """List titled top-level Windows windows and their geometry/state."""
    return _json_call(lambda: bridge.list_windows(source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def window_control(title: str, operation: str) -> str:
    """Activate, minimize, maximize, restore, or close the first matching window."""
    return _json_call(lambda: bridge.window_control(title, operation, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def uia_tree(title_re: str = ".*", depth: int = 4, max_elements: int = 500) -> str:
    """Inspect a Windows UI Automation tree with names, types, IDs, and rectangles."""
    return _json_call(lambda: bridge.uia_tree(title_re, depth, max_elements, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def uia_invoke(
    title_re: str,
    selector: dict[str, Any],
    action: str = "click",
    value: str | None = None,
) -> str:
    """Interact with a UI element by semantic selector instead of screen coordinates."""
    return _json_call(
        lambda: bridge.uia_invoke(title_re, selector, action, value, source="mcp")
    )


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
def registry_get(hive: str, key: str, value_name: str = "") -> str:
    """Read a Windows registry value. Enabled in full profile."""
    return _json_call(lambda: bridge.registry_get(hive, key, value_name, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
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


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def registry_delete(hive: str, key: str, value_name: str | None = None) -> str:
    """Delete a registry value or key. Enabled in full profile."""
    return _json_call(lambda: bridge.registry_delete(hive, key, value_name, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def service_control(service_name: str, operation: str) -> str:
    """Query/start/stop/pause/continue/restart a Windows service."""
    return _json_call(lambda: bridge.service_control(service_name, operation, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True})
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


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True})
def network_admin(operation: str, target: str | None = None) -> str:
    """Inspect networking, flush DNS, ping, or resolve a target."""
    return _json_call(lambda: bridge.network_admin(operation, target, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def scheduled_task_control(
    operation: str,
    task_name: str,
    command: str | None = None,
    schedule: str | None = None,
) -> str:
    """Query/run/end/delete/create a Windows scheduled task."""
    return _json_call(
        lambda: bridge.scheduled_task_control(
            operation,
            task_name,
            command,
            schedule,
            source="mcp",
        )
    )


@mcp.tool(annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False})
def power_control(operation: str, delay_seconds: int = 0) -> str:
    """Shutdown, restart, log off, abort shutdown, lock, or sleep Windows."""
    return _json_call(lambda: bridge.power_control(operation, delay_seconds, source="mcp"))


@mcp.tool(annotations={"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False})
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
