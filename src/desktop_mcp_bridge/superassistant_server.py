from __future__ import annotations

import asyncio
import inspect
from typing import Any

from .server import mcp


def _set_attribute(target: Any, name: str, value: Any) -> bool:
    if target is None or not hasattr(target, name):
        return False
    try:
        setattr(target, name, value)
    except (AttributeError, TypeError):
        object.__setattr__(target, name, value)
    return True


def apply_superassistant_compatibility(server: Any = mcp) -> dict[str, Any]:
    """Disable structured-output schemas for the MCP SuperAssistant process.

    Current MCP SuperAssistant releases have open tool-discovery bugs when a
    ``tools/list`` response includes ``outputSchema``. The standard bridge MCP
    entry point remains unchanged; only this dedicated process mutates its
    in-memory FastMCP registrations.

    FastMCP does not currently expose a public bulk switch for registrations
    that already exist, so this adapter intentionally probes the v1.x tool
    manager metadata and fails closed when the expected registrations are not
    available.
    """

    manager = getattr(server, "_tool_manager", None)
    list_tools = getattr(manager, "list_tools", None)
    if not callable(list_tools):
        raise RuntimeError("FastMCP tool manager is unavailable; SuperAssistant compatibility failed")

    tools = list_tools()
    if inspect.isawaitable(tools):
        tools = asyncio.run(tools)
    registered = list(tools)
    if not registered:
        raise RuntimeError("No MCP tools are registered; refusing to start an empty proxy server")

    modified: list[str] = []
    unsupported: list[str] = []
    for tool in registered:
        name = str(getattr(tool, "name", "<unnamed>"))
        metadata = getattr(tool, "fn_metadata", None)
        changed = False
        changed = _set_attribute(metadata, "output_schema", None) or changed
        changed = _set_attribute(metadata, "wrap_output", False) or changed
        changed = _set_attribute(tool, "output_schema", None) or changed
        if changed:
            modified.append(name)
        else:
            unsupported.append(name)

    if unsupported:
        names = ", ".join(unsupported[:10])
        raise RuntimeError(
            "FastMCP tool metadata changed and compatibility could not be applied to: " + names
        )

    return {
        "registered_tools": len(registered),
        "modified_tools": len(modified),
        "tool_names": modified,
    }


def run() -> None:
    apply_superassistant_compatibility(mcp)
    mcp.run(transport="stdio")


if __name__ == "__main__":
    run()
