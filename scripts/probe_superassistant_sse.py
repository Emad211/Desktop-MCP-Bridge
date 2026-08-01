"""Probe SuperAssistant's browser-facing SSE transport at the wire level.

The browser extension uses an EventSource connection to ``/sse`` and POSTs MCP
JSON-RPC messages to the session-specific endpoint announced by the SSE stream.
This probe follows that exact transport flow without depending on ChatGPT's DOM.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import sys
import traceback
from typing import Any
from urllib.parse import urljoin

import httpx


REQUIRED_TOOLS = {
    "bridge_status",
    "read_text_file",
    "write_text_file",
    "run_command",
}


def describe_exception(exc: BaseException) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": type(exc).__name__,
        "message": str(exc),
    }
    if isinstance(exc, BaseExceptionGroup):
        payload["exceptions"] = [describe_exception(item) for item in exc.exceptions]
    else:
        rendered = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        payload["traceback"] = rendered[-8000:]
    return payload


async def read_sse_events(
    response: httpx.Response,
    endpoint_future: asyncio.Future[str],
    messages: asyncio.Queue[dict[str, Any]],
) -> None:
    event_name = "message"
    data_lines: list[str] = []

    async def dispatch() -> None:
        nonlocal event_name, data_lines
        if not data_lines:
            event_name = "message"
            return
        data = "\n".join(data_lines)
        if event_name == "endpoint":
            if not endpoint_future.done():
                endpoint_future.set_result(data)
        elif event_name == "message":
            try:
                payload = json.loads(data)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"SSE message was not valid JSON: {data!r}") from exc
            if not isinstance(payload, dict):
                raise RuntimeError("SSE JSON-RPC payload was not an object")
            await messages.put(payload)
        event_name = "message"
        data_lines = []

    try:
        async for line in response.aiter_lines():
            if line == "":
                await dispatch()
                continue
            if line.startswith(":"):
                continue
            field, separator, value = line.partition(":")
            if not separator:
                continue
            value = value[1:] if value.startswith(" ") else value
            if field == "event":
                event_name = value or "message"
            elif field == "data":
                data_lines.append(value)
        await dispatch()
        if not endpoint_future.done():
            endpoint_future.set_exception(
                RuntimeError("SSE stream closed before announcing the message endpoint")
            )
    except BaseException as exc:
        if not endpoint_future.done():
            endpoint_future.set_exception(exc)
        raise


async def probe(endpoint: str, timeout: float) -> dict[str, Any]:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout

    def remaining() -> float:
        value = deadline - loop.time()
        if value <= 0:
            raise TimeoutError(f"SSE probe exceeded {timeout:g} seconds")
        return value

    client_timeout = httpx.Timeout(connect=10.0, read=None, write=10.0, pool=10.0)
    async with httpx.AsyncClient(
        timeout=client_timeout,
        follow_redirects=True,
        trust_env=False,
    ) as client:
        async with client.stream(
            "GET",
            endpoint,
            headers={"Accept": "text/event-stream"},
        ) as response:
            response.raise_for_status()
            content_type = response.headers.get("content-type", "")
            if "text/event-stream" not in content_type.lower():
                raise RuntimeError(
                    f"Expected text/event-stream but received {content_type!r}"
                )

            endpoint_future: asyncio.Future[str] = loop.create_future()
            messages: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
            reader_task = asyncio.create_task(
                read_sse_events(response, endpoint_future, messages)
            )

            try:
                announced_endpoint = await asyncio.wait_for(
                    endpoint_future, timeout=remaining()
                )
                message_url = urljoin(endpoint, announced_endpoint)

                async def post(payload: dict[str, Any]) -> None:
                    post_response = await asyncio.wait_for(
                        client.post(
                            message_url,
                            json=payload,
                            headers={"Content-Type": "application/json"},
                        ),
                        timeout=remaining(),
                    )
                    if post_response.status_code not in {200, 202, 204}:
                        raise RuntimeError(
                            "MCP message POST failed: "
                            f"HTTP {post_response.status_code} {post_response.text[:1000]!r}"
                        )

                async def wait_for_response(request_id: int) -> dict[str, Any]:
                    while True:
                        payload = await asyncio.wait_for(
                            messages.get(), timeout=remaining()
                        )
                        if payload.get("id") != request_id:
                            continue
                        if "error" in payload:
                            raise RuntimeError(
                                f"JSON-RPC request {request_id} failed: {payload['error']!r}"
                            )
                        result = payload.get("result")
                        if not isinstance(result, dict):
                            raise RuntimeError(
                                f"JSON-RPC request {request_id} returned no object result"
                            )
                        return result

                await post(
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {
                            "protocolVersion": "2025-03-26",
                            "capabilities": {},
                            "clientInfo": {
                                "name": "desktop-mcp-bridge-sse-probe",
                                "version": "1.0.0",
                            },
                        },
                    }
                )
                initialize_result = await wait_for_response(1)

                await post(
                    {
                        "jsonrpc": "2.0",
                        "method": "notifications/initialized",
                    }
                )

                await post(
                    {
                        "jsonrpc": "2.0",
                        "id": 2,
                        "method": "tools/list",
                        "params": {},
                    }
                )
                tools_result = await wait_for_response(2)
                raw_tools = tools_result.get("tools")
                if not isinstance(raw_tools, list):
                    raise RuntimeError("tools/list returned no tools array")
                tool_names = sorted(
                    str(tool.get("name"))
                    for tool in raw_tools
                    if isinstance(tool, dict) and tool.get("name")
                )
                missing = sorted(REQUIRED_TOOLS.difference(tool_names))
                if missing:
                    raise RuntimeError(
                        f"SSE tools/list is missing required tools: {', '.join(missing)}"
                    )

                await post(
                    {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {
                            "name": "bridge_status",
                            "arguments": {},
                        },
                    }
                )
                status_result = await wait_for_response(3)
                if status_result.get("isError") is True:
                    raise RuntimeError("bridge_status returned isError=true over SSE")
                content = status_result.get("content")
                if not isinstance(content, list) or not content:
                    raise RuntimeError("bridge_status returned no content blocks over SSE")

                return {
                    "ok": True,
                    "endpoint": endpoint,
                    "announced_message_endpoint": announced_endpoint,
                    "message_url": message_url,
                    "protocol_version": initialize_result.get("protocolVersion"),
                    "server_info": initialize_result.get("serverInfo"),
                    "tool_count": len(tool_names),
                    "required_tools_present": sorted(REQUIRED_TOOLS),
                    "bridge_status_content_blocks": len(content),
                    "bridge_status_is_error": bool(status_result.get("isError", False)),
                    "transport_probe": "wire-level-eventsource-post",
                }
            finally:
                reader_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await reader_task


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Probe a SuperAssistant SSE endpoint at the wire level."
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
    except BaseException as exc:  # noqa: BLE001 - CLI boundary emits diagnostics
        error = {
            "ok": False,
            "endpoint": args.endpoint,
            "exception": describe_exception(exc),
        }
        print(json.dumps(error, ensure_ascii=False, indent=2))
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
