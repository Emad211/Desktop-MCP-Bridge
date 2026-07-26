from __future__ import annotations

import inspect
import json
import secrets
import threading
import time
from collections import defaultdict, deque
from typing import Any, Callable

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from .config import BridgeSettings
from .runtime import DesktopBridge

settings = BridgeSettings()
bridge = DesktopBridge(settings)
app = FastAPI(
    title="Desktop Bridge GPT Action Gateway",
    version="0.2.0",
    description=(
        "Authenticated text-only gateway for a private Custom GPT. Use observe for read-only "
        "operations and act for state-changing operations."
    ),
)
security = HTTPBearer(auto_error=False)
_RATE_LOCK = threading.Lock()
_RATE_WINDOWS: dict[str, deque[float]] = defaultdict(deque)


class DispatchRequest(BaseModel):
    operation: str = Field(min_length=1, max_length=100)
    arguments: dict[str, Any] = Field(default_factory=dict)


def require_api_key(
    credentials: HTTPAuthorizationCredentials | None = Depends(security),
) -> None:
    if not settings.action_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="DMB_ACTION_API_KEY is not configured",
        )
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bearer token required")
    if not secrets.compare_digest(credentials.credentials, settings.action_api_key):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid API key")


def rate_limit(request: Request) -> None:
    key = request.client.host if request.client else "unknown"
    now = time.monotonic()
    with _RATE_LOCK:
        window = _RATE_WINDOWS[key]
        while window and now - window[0] > 60:
            window.popleft()
        if len(window) >= 120:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        window.append(now)


def _bounded(payload: Any) -> dict[str, Any]:
    rendered = json.dumps(payload, ensure_ascii=False, default=str)
    if len(rendered) <= 90_000:
        return {"ok": True, "result": payload}
    return {
        "ok": True,
        "result": {
            "truncated": True,
            "content": rendered[:89_000],
            "message": "Response truncated to stay below GPT Action payload limits.",
        },
    }


def _dispatch(
    operation: str,
    arguments: dict[str, Any],
    table: dict[str, Callable[..., Any]],
) -> dict[str, Any]:
    callback = table.get(operation)
    if callback is None:
        raise HTTPException(status_code=400, detail=f"Unknown operation: {operation}")
    try:
        normalized_arguments = dict(arguments)
        parameters = inspect.signature(callback).parameters
        if (
            "operation" in normalized_arguments
            and "operation_name" in parameters
            and "operation_name" not in normalized_arguments
        ):
            normalized_arguments["operation_name"] = normalized_arguments.pop("operation")
        return _bounded(callback(**normalized_arguments, source="gpt-action"))
    except TypeError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        return {"ok": False, "error": type(exc).__name__, "message": str(exc)}


READ_OPERATIONS: dict[str, Callable[..., Any]] = {
    "status": bridge.status,
    "system_info": bridge.system_info,
    "list_directory": bridge.list_directory,
    "read_text_file": bridge.read_text_file,
    "read_binary_file": bridge.read_binary_file,
    "get_command_job": bridge.get_command_job,
    "list_command_jobs": bridge.list_command_jobs,
    "list_processes": bridge.list_processes,
    "clipboard_read": bridge.clipboard_read,
    "list_windows": bridge.list_windows,
    "uia_tree": bridge.uia_tree,
    "registry_get": bridge.registry_get,
    "audit_tail": bridge.audit_tail,
}

WRITE_OPERATIONS: dict[str, Callable[..., Any]] = {
    "desktop_step": bridge.desktop_step,
    "write_text_file": bridge.write_text_file,
    "write_binary_file": bridge.write_binary_file,
    "copy_path": bridge.copy_path,
    "move_path": bridge.move_path,
    "delete_path": bridge.delete_path,
    "run_command": bridge.run_command,
    "start_command_job": bridge.start_command_job,
    "cancel_command_job": bridge.cancel_command_job,
    "stop_process": bridge.stop_process,
    "clipboard_write": bridge.clipboard_write,
    "window_control": bridge.window_control,
    "uia_invoke": bridge.uia_invoke,
    "registry_set": bridge.registry_set,
    "registry_delete": bridge.registry_delete,
    "service_control": bridge.service_control,
    "package_manage": bridge.package_manage,
    "network_admin": bridge.network_admin,
    "scheduled_task_control": bridge.scheduled_task_control,
    "power_control": bridge.power_control,
}


@app.get("/health", operation_id="healthCheck")
def health_check() -> dict[str, Any]:
    return {"ok": True, "service": "desktop-bridge-action-gateway", "version": "0.2.0"}


@app.post(
    "/v1/observe",
    operation_id="observeComputer",
    dependencies=[Depends(require_api_key), Depends(rate_limit)],
)
def observe(request: DispatchRequest) -> dict[str, Any]:
    """Run a read-only desktop/system operation and return text/JSON."""
    return _dispatch(request.operation, request.arguments, READ_OPERATIONS)


@app.post(
    "/v1/act",
    operation_id="controlComputer",
    dependencies=[Depends(require_api_key), Depends(rate_limit)],
)
def act(request: DispatchRequest) -> dict[str, Any]:
    """Run a state-changing desktop/system operation."""
    return _dispatch(request.operation, request.arguments, WRITE_OPERATIONS)


def run_action_api() -> None:
    uvicorn.run(
        "desktop_mcp_bridge.action_api:app",
        host=settings.action_host,
        port=settings.action_port,
        reload=False,
        access_log=True,
    )
