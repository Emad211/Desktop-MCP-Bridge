from __future__ import annotations

import os
import shlex
from pathlib import Path

from .config import BridgeSettings


class SecurityViolation(PermissionError):
    """Raised when an operation falls outside the configured policy."""


def resolve_allowed_path(path: str | Path, settings: BridgeSettings, *, must_exist: bool = False) -> Path:
    candidate = Path(path).expanduser()
    try:
        resolved = candidate.resolve(strict=must_exist)
    except OSError as exc:
        raise SecurityViolation(f"Unable to resolve path: {candidate}") from exc

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

    normalized = " ".join(command.lower().split())
    for fragment in settings.blocked_command_fragments:
        if fragment.lower() in normalized:
            raise SecurityViolation(f"Command contains blocked fragment: {fragment}")

    executable = _first_executable(command)
    allowed = {item.lower() for item in settings.allowed_executables}
    if executable.lower() not in allowed:
        raise SecurityViolation(f"Executable is not allowlisted: {executable}")

    if executable.lower() in {"powershell", "pwsh"} and not settings.allow_powershell:
        raise SecurityViolation("PowerShell is disabled")


def _first_executable(command: str) -> str:
    try:
        parts = shlex.split(command, posix=os.name != "nt")
    except ValueError as exc:
        raise SecurityViolation(f"Unable to parse command: {exc}") from exc
    if not parts:
        raise SecurityViolation("Command is empty")
    return Path(parts[0]).name
