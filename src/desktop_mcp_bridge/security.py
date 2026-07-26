from __future__ import annotations

import os
import re
import shlex
from pathlib import Path
from typing import Any

from .config import BridgeSettings


class SecurityViolation(PermissionError):
    """Raised when an operation falls outside the configured policy."""


MUTATING_ACTIONS = {
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
    "registry_set",
    "registry_delete",
    "service_control",
    "package_manage",
    "network_admin",
    "scheduled_task_control",
    "power_control",
}


def check_kill_switch(settings: BridgeSettings, action: str) -> None:
    if action in MUTATING_ACTIONS and settings.kill_switch_path.exists():
        raise SecurityViolation(
            f"Kill switch is active: {settings.kill_switch_path}. Remove it locally to resume."
        )


def resolve_allowed_path(
    path: str | Path,
    settings: BridgeSettings,
    *,
    must_exist: bool = False,
) -> Path:
    candidate = Path(path).expanduser()
    try:
        resolved = candidate.resolve(strict=must_exist)
    except OSError as exc:
        raise SecurityViolation(f"Unable to resolve path: {candidate}") from exc

    if settings.is_full_access:
        return resolved

    for root in settings.allowed_roots:
        try:
            resolved.relative_to(root)
            return resolved
        except ValueError:
            continue
    roots = ", ".join(str(root) for root in settings.allowed_roots)
    raise SecurityViolation(f"Path is outside allowed roots: {resolved}. Allowed: {roots}")


def validate_command(command: str, settings: BridgeSettings) -> None:
    if not settings.enable_shell:
        raise SecurityViolation("Shell tools are disabled")

    if settings.is_full_access:
        return

    normalized = " ".join(command.lower().split())
    for fragment in settings.blocked_command_fragments:
        if fragment.lower() in normalized:
            raise SecurityViolation(f"Command contains blocked fragment: {fragment}")

    executable = first_executable(command)
    allowed = {item.lower() for item in settings.allowed_executables}
    if executable.lower() not in allowed:
        raise SecurityViolation(f"Executable is not allowlisted: {executable}")

    if executable.lower() in {"powershell", "pwsh"} and not settings.allow_powershell:
        raise SecurityViolation("PowerShell is disabled")


def require_capability(settings: BridgeSettings, capability: str) -> None:
    value = getattr(settings, capability, False)
    if not value:
        raise SecurityViolation(f"Capability is disabled: {capability}")


def require_full_access(settings: BridgeSettings, operation: str) -> None:
    if not settings.is_full_access:
        raise SecurityViolation(f"{operation} requires access_profile=full")


def first_executable(command: str) -> str:
    try:
        parts = shlex.split(command, posix=os.name != "nt")
    except ValueError as exc:
        raise SecurityViolation(f"Unable to parse command: {exc}") from exc
    if not parts:
        raise SecurityViolation("Command is empty")
    return Path(parts[0]).name


def redact(value: Any) -> Any:
    """Redact common credential fields before audit logging."""
    secret_markers = ("password", "passwd", "secret", "token", "api_key", "apikey", "authorization")
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            result[key] = "***REDACTED***" if any(marker in key.lower() for marker in secret_markers) else redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, tuple):
        return tuple(redact(item) for item in value)
    if isinstance(value, str):
        patterns = [
            r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+",
            r"(?i)((?:password|passwd|secret|token|api[_-]?key)\s*[:=]\s*)[^\s,;]+",
            r"(?i)((?:--password|--passwd|--secret|--token|--api-key)\s+)[^\s]+",
        ]
        redacted = value
        for pattern in patterns:
            redacted = re.sub(pattern, r"\1***REDACTED***", redacted)
        return redacted
    return value
