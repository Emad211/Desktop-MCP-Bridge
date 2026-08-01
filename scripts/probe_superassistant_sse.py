"""Probe the SuperAssistant SSE endpoint as a real MCP client.

This verifies the exact transport path used by the browser extension:
SSE client -> local SuperAssistant proxy -> Desktop MCP Bridge.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

from mcp import ClientSession
from mcp.client.sse import sse_client


async def probe(endpoint: str, timeout: float) -> dict[str, Any]:
    async def _run() -> dict[str, Any]:
        async with sse_client(endpoint) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                initialize_result = await session.initialize()
                tools_result = await session.list_tools()
                tool_names = sorted(tool.name for tool in tools_result.tools)
                required = {
                    "bridge_status",
                    "read_text_file",
                    "write_text_file",
                    "run_command",
                }
                missing = sorted(required.difference(tool_names))
                if missing:
                    raise RuntimeError(
                        f"SSE tools/list is missing required tools: {', '.join(missing)}"
                    )

                status_result = await session.call_tool("bridge_status", {})
                if status_result.isError:
                    raise RuntimeError("bridge_status returned isError=true over SSE")

                return {
                    "ok": True,
                    "endpoint": endpoint,
                    "protocol_version": initialize_result.protocolVersion,
                    "server_info": initialize_result.serverInfo.model_dump(
                        mode="json", exclude_none=True
                    ),
                    "tool_count": len(tool_names),
                    "required_tools_present": sorted(required),
                    "bridge_status_content_blocks": len(status_result.content),
                    "bridge_status_is_error": bool(status_result.isError),
                }

    return await asyncio.wait_for(_run(), timeout=timeout)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Probe a SuperAssistant SSE endpoint as an MCP client."
    )
    parser.add_argument(
        "--endpoint", default="http://localhost:3006/sse", help="SSE endpoint URL"
    )
    parser.add_argument(
        "--timeout", type=float, default=45.0, help="Overall timeout in seconds"
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        result = asyncio.run(probe(args.endpoint, args.timeout))
    except Exception as exc:  # noqa: BLE001 - CLI boundary must emit structured error
        error = {
            "ok": False,
            "endpoint": args.endpoint,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }
        print(json.dumps(error, ensure_ascii=False, indent=2))
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
