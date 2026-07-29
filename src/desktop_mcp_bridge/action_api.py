from __future__ import annotations

import inspect
import json
import secrets
import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from typing import Annotated, Any, Literal

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from . import __version__
from .config import BridgeSettings
from .idempotency import IdempotencyCache
from .runtime import DesktopBridge
from .security import HIGH_RISK_ACTIONS

settings = BridgeSettings()
bridge = DesktopBridge(settings)
app = FastAPI(
    title="Desktop Bridge GPT Action Gateway",
    version=__version__,
    description=(
        "Authenticated gateway for a private Custom GPT. It exposes structured Windows, browser, "
        "filesystem, shell, UI Automation, OCR, and short-lived screenshot artifact operations."
    ),
)
security = HTTPBearer(auto_error=False)
_RATE_LOCK = threading.Lock()
_RATE_WINDOWS: dict[str, deque[float]] = defaultdict(deque)
_IDEMPOTENCY = IdempotencyCache(
    ttl_seconds=settings.idempotency_ttl_seconds,
    path=settings.idempotency_path,
)

ReadOperation = Literal[
    "status",
    "system_info",
    "capture_desktop_artifact",
    "screen_ocr",
    "list_directory",
    "read_text_file",
    "read_binary_file",
    "get_command_job",
    "list_command_jobs",
    "list_processes",
    "clipboard_read",
    "list_windows",
    "uia_tree",
    "browser_status",
    "browser_snapshot",
    "browser_screenshot",
    "registry_get",
    "audit_tail",
]

WriteOperation = Literal[
    "desktop_step",
    "write_text_file",
    "write_binary_file",
    "copy_path",
    "move_path",
    "delete_path",
    "run_command",
    "start_command_job",
    "cancel_command_job",
    "stop_process",
    "clipboard_write",
    "window_control",
    "uia_invoke",
    "browser_start",
    "browser_navigate",
    "browser_interact",
    "browser_tabs",
    "browser_upload",
    "browser_download",
    "browser_evaluate",
    "browser_close",
    "registry_set",
    "registry_delete",
    "service_control",
    "package_manage",
    "network_admin",
    "scheduled_task_control",
    "power_control",
]


class ObserveRequest(BaseModel):
    operation: ReadOperation
    arguments: dict[str, Any] = Field(default_factory=dict)


class ActRequest(BaseModel):
    operation: WriteOperation
    arguments: dict[str, Any] = Field(default_factory=dict)
    request_id: str = Field(min_length=8, max_length=100)
    confirmation: str | None = Field(
        default=None,
        description="In guarded mode, high-risk actions require CONFIRM:<operation>.",
    )


def require_api_key(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
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
        if len(window) >= settings.action_rate_limit_per_minute:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        window.append(now)


@app.middleware("http")
async def enforce_payload_limit(request: Request, call_next: Callable[..., Any]) -> Response:
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            too_large = int(content_length) > 1_000_000
        except ValueError:
            return Response(content="Invalid Content-Length", status_code=400)
        if too_large:
            return Response(content="Request body too large", status_code=413)
    return await call_next(request)


def _bounded(payload: Any) -> dict[str, Any]:
    rendered = json.dumps(payload, ensure_ascii=False, default=str)
    if len(rendered) <= settings.action_max_payload_chars:
        return {"ok": True, "result": payload}
    return {
        "ok": True,
        "result": {
            "truncated": True,
            "content": rendered[: settings.action_max_payload_chars - 1_000],
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


def _add_artifact_urls(value: Any, base_url: str) -> Any:
    if isinstance(value, dict):
        mapped = {key: _add_artifact_urls(item, base_url) for key, item in value.items()}
        token = mapped.get("token")
        artifact_id = mapped.get("artifact_id")
        if token and artifact_id and "url" not in mapped:
            mapped["url"] = f"{base_url.rstrip('/')}/v1/artifacts/{token}"
        return mapped
    if isinstance(value, list):
        return [_add_artifact_urls(item, base_url) for item in value]
    return value


READ_OPERATIONS: dict[str, Callable[..., Any]] = {
    "status": bridge.status,
    "system_info": bridge.system_info,
    "capture_desktop_artifact": bridge.capture_desktop_artifact,
    "screen_ocr": bridge.screen_ocr,
    "list_directory": bridge.list_directory,
    "read_text_file": bridge.read_text_file,
    "read_binary_file": bridge.read_binary_file,
    "get_command_job": bridge.get_command_job,
    "list_command_jobs": bridge.list_command_jobs,
    "list_processes": bridge.list_processes,
    "clipboard_read": bridge.clipboard_read,
    "list_windows": bridge.list_windows,
    "uia_tree": bridge.uia_tree,
    "browser_status": bridge.browser_status,
    "browser_snapshot": bridge.browser_snapshot,
    "browser_screenshot": bridge.browser_screenshot,
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
    "browser_start": bridge.browser_start,
    "browser_navigate": bridge.browser_navigate,
    "browser_interact": bridge.browser_interact,
    "browser_tabs": bridge.browser_tabs,
    "browser_upload": bridge.browser_upload,
    "browser_download": bridge.browser_download,
    "browser_evaluate": bridge.browser_evaluate,
    "browser_close": bridge.browser_close,
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
    return {
        "ok": True,
        "service": "desktop-bridge-action-gateway",
        "version": __version__,
    }


@app.get("/privacy", response_class=PlainTextResponse, include_in_schema=False)
def privacy() -> str:
    return (
        "Desktop MCP Bridge is a self-hosted local agent. Requests are processed on the operator's "
        "Windows computer. Audit records are stored locally. The project does not send data to an "
        "OpenAI API. Data sent through a Custom GPT Action is still subject to ChatGPT data controls."
    )


@app.post(
    "/v1/observe",
    operation_id="observeComputer",
    dependencies=[Depends(require_api_key), Depends(rate_limit)],
    openapi_extra={"x-openai-isConsequential": False},
)
def observe(request: ObserveRequest, http_request: Request) -> dict[str, Any]:
    """Run a read-only desktop/system/browser operation and return JSON."""
    response = _dispatch(request.operation, request.arguments, READ_OPERATIONS)
    return _add_artifact_urls(response, str(http_request.base_url))


@app.post(
    "/v1/act",
    operation_id="controlComputer",
    dependencies=[Depends(require_api_key), Depends(rate_limit)],
    openapi_extra={"x-openai-isConsequential": True},
)
def act(request: ActRequest, http_request: Request) -> dict[str, Any]:
    """Run an idempotent state-changing operation."""
    if settings.approval_policy == "guarded" and request.operation in HIGH_RISK_ACTIONS:
        required = f"CONFIRM:{request.operation}"
        if request.confirmation != required:
            raise HTTPException(
                status_code=409,
                detail={
                    "message": "This high-risk operation requires explicit confirmation.",
                    "required_confirmation": required,
                },
            )

    request_hash = _IDEMPOTENCY.request_hash(request.operation, request.arguments)
    try:
        cached = _IDEMPOTENCY.begin(request.request_id, request_hash)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=425, detail=str(exc)) from exc
    if cached is not None:
        return {**cached, "idempotent_replay": True}

    try:
        response = _dispatch(request.operation, request.arguments, WRITE_OPERATIONS)
        response = _add_artifact_urls(response, str(http_request.base_url))
        if response.get("ok") is False:
            _IDEMPOTENCY.abandon(request.request_id)
            return response
        _IDEMPOTENCY.complete(request.request_id, response)
        return response
    except Exception:
        _IDEMPOTENCY.abandon(request.request_id)
        raise


@app.get(
    "/v1/screenshot",
    operation_id="getScreenCapture",
    dependencies=[Depends(require_api_key), Depends(rate_limit)],
    responses={
        200: {
            "description": "Current desktop screenshot",
            "content": {"image/png": {"schema": {"type": "string", "format": "binary"}}},
        }
    },
    openapi_extra={"x-openai-isConsequential": False},
)
def screenshot(
    monitor: int = 1,
    max_width: int = 1920,
) -> Response:
    data, _ = bridge.observe_desktop_bytes(
        monitor=monitor, max_width=max_width, image_format="png", source="gpt-action"
    )
    return Response(
        content=data,
        media_type="image/png",
        headers={"Cache-Control": "no-store"},
    )


@app.get(
    "/v1/artifacts/{token}",
    include_in_schema=False,
    dependencies=[Depends(rate_limit)],
)
def artifact_download(token: str) -> FileResponse:
    try:
        artifact = bridge.artifacts.resolve(token)
    except (FileNotFoundError, PermissionError) as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return FileResponse(
        path=artifact.path,
        filename=artifact.filename,
        media_type=artifact.mime_type,
        headers={"Cache-Control": "private, max-age=60"},
    )


@app.on_event("shutdown")
def shutdown() -> None:
    bridge.close()


def run_action_api() -> None:
    uvicorn.run(
        "desktop_mcp_bridge.action_api:app",
        host=settings.action_host,
        port=settings.action_port,
        reload=False,
        access_log=True,
        proxy_headers=True,
        forwarded_allow_ips="127.0.0.1",
    )
