from __future__ import annotations

import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, TextIO


class ProbeFailure(RuntimeError):
    pass


def _reader(stream: TextIO, output: queue.Queue[str | None]) -> None:
    try:
        for line in iter(stream.readline, ""):
            output.put(line.rstrip("\r\n"))
    finally:
        output.put(None)


def _send(process: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    if process.stdin is None:
        raise ProbeFailure("MCP child stdin is unavailable")
    process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    process.stdin.flush()


def _receive_response(
    process: subprocess.Popen[str],
    stdout_queue: queue.Queue[str | None],
    request_id: int,
    timeout_seconds: float,
    observed: list[dict[str, Any]],
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if process.poll() is not None and stdout_queue.empty():
            raise ProbeFailure(f"MCP child exited with code {process.returncode}")
        remaining = max(0.05, deadline - time.monotonic())
        try:
            line = stdout_queue.get(timeout=min(0.25, remaining))
        except queue.Empty:
            continue
        if line is None:
            if process.poll() is not None:
                raise ProbeFailure(f"MCP child stdout closed with code {process.returncode}")
            continue
        if not line.strip():
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            observed.append({"non_json_stdout": line[:2_000]})
            continue
        observed.append(message)
        if message.get("id") == request_id:
            if "error" in message:
                raise ProbeFailure(
                    f"MCP request {request_id} failed: "
                    + json.dumps(message["error"], ensure_ascii=False)
                )
            result = message.get("result")
            if not isinstance(result, dict):
                raise ProbeFailure(f"MCP request {request_id} returned no object result")
            return result
    raise ProbeFailure(f"Timed out waiting for MCP response id={request_id}")


def run_probe(config_path: Path, server_name: str, timeout_seconds: float) -> dict[str, Any]:
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    servers = config.get("mcpServers")
    if not isinstance(servers, dict) or server_name not in servers:
        raise ProbeFailure(f"Server {server_name!r} is missing from {config_path}")
    server = servers[server_name]
    if not isinstance(server, dict):
        raise ProbeFailure("Configured server entry must be an object")

    command = str(server.get("command") or "")
    args = [str(item) for item in server.get("args", [])]
    if not command:
        raise ProbeFailure("Configured MCP command is empty")
    if not Path(command).exists() and not shutil_which(command):
        raise ProbeFailure(f"Configured MCP command was not found: {command}")

    environment = os.environ.copy()
    configured_environment = server.get("env", {})
    if not isinstance(configured_environment, dict):
        raise ProbeFailure("Configured env must be an object")
    environment.update({str(key): str(value) for key, value in configured_environment.items()})
    cwd_value = server.get("cwd")
    cwd = None if not cwd_value else str(Path(str(cwd_value)).expanduser().resolve())

    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)

    process = subprocess.Popen(
        [command, *args],
        cwd=cwd,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        creationflags=creationflags,
    )
    if process.stdout is None or process.stderr is None:
        process.kill()
        raise ProbeFailure("MCP child pipes are unavailable")

    stdout_queue: queue.Queue[str | None] = queue.Queue()
    stderr_queue: queue.Queue[str | None] = queue.Queue()
    threading.Thread(target=_reader, args=(process.stdout, stdout_queue), daemon=True).start()
    threading.Thread(target=_reader, args=(process.stderr, stderr_queue), daemon=True).start()

    observed: list[dict[str, Any]] = []
    try:
        _send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "desktop-mcp-bridge-stdio-probe",
                        "version": "1.0.0",
                    },
                },
            },
        )
        initialize = _receive_response(
            process, stdout_queue, 1, timeout_seconds, observed
        )
        _send(process, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        _send(
            process,
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        )
        tools_result = _receive_response(
            process, stdout_queue, 2, timeout_seconds, observed
        )
        tools = tools_result.get("tools")
        if not isinstance(tools, list) or not tools:
            raise ProbeFailure("tools/list returned no tools")

        names = [str(tool.get("name")) for tool in tools if isinstance(tool, dict)]
        expected = {
            "bridge_status",
            "run_command",
            "start_command_job",
            "browser_snapshot",
            "uia_tree",
        }
        missing = sorted(expected.difference(names))
        if missing:
            raise ProbeFailure("Missing expected MCP tools: " + ", ".join(missing))
        with_output_schema = [
            str(tool.get("name"))
            for tool in tools
            if isinstance(tool, dict) and tool.get("outputSchema") is not None
        ]
        if with_output_schema:
            raise ProbeFailure(
                "SuperAssistant compatibility still exposes outputSchema for: "
                + ", ".join(with_output_schema[:20])
            )

        _send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "bridge_status", "arguments": {}},
            },
        )
        status_result = _receive_response(
            process, stdout_queue, 3, timeout_seconds, observed
        )
        if status_result.get("isError") is True:
            raise ProbeFailure("bridge_status returned isError=true")
        content = status_result.get("content")
        if not isinstance(content, list) or not content:
            raise ProbeFailure("bridge_status returned no content")

        return {
            "ok": True,
            "server_name": server_name,
            "command": command,
            "args": args,
            "protocol_version": initialize.get("protocolVersion"),
            "server_info": initialize.get("serverInfo"),
            "tool_count": len(tools),
            "expected_tools_present": sorted(expected),
            "tools_with_output_schema": with_output_schema,
            "bridge_status_content_blocks": len(content),
        }
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def shutil_which(command: str) -> str | None:
    from shutil import which

    return which(command)


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe a configured MCP stdio server")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--server", default="desktop-mcp-bridge")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    try:
        result = run_probe(args.config.expanduser().resolve(), args.server, args.timeout)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
                ensure_ascii=False,
                indent=2,
            ),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
