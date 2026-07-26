from __future__ import annotations

from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class BridgeSettings(BaseSettings):
    """Runtime settings. Environment variables use the DMB_ prefix."""

    model_config = SettingsConfigDict(env_prefix="DMB_", env_nested_delimiter="__")

    transport: Literal["stdio", "streamable-http", "sse"] = "stdio"
    host: str = "127.0.0.1"
    port: int = Field(default=8765, ge=1024, le=65535)
    allowed_roots: list[Path] = Field(default_factory=lambda: [Path.cwd()])
    max_read_bytes: int = Field(default=2_000_000, ge=1_024, le=50_000_000)
    max_write_bytes: int = Field(default=2_000_000, ge=1_024, le=50_000_000)
    command_timeout_seconds: int = Field(default=120, ge=1, le=3600)
    enable_desktop_control: bool = True
    enable_shell: bool = True
    enable_process_control: bool = False
    enable_delete: bool = False
    allow_powershell: bool = True
    allowed_executables: list[str] = Field(
        default_factory=lambda: [
            "cmd", "powershell", "pwsh", "python", "python3", "py", "git", "node", "npm",
            "npx", "pnpm", "yarn", "dotnet", "java", "javac", "gradle", "gradlew",
        ]
    )
    blocked_command_fragments: list[str] = Field(
        default_factory=lambda: [
            "format ", "diskpart", "cipher /w", "bcdedit", "reg delete", "shutdown ",
            "restart-computer", "stop-computer", "remove-item -recurse", "rm -rf",
            "del /s", "rd /s", "rmdir /s", "net user", "net localgroup administrators",
        ]
    )

    @field_validator("allowed_roots", mode="after")
    @classmethod
    def normalize_roots(cls, roots: list[Path]) -> list[Path]:
        return [root.expanduser().resolve() for root in roots]


class DesktopAction(BaseModel):
    type: Literal["click", "double_click", "move", "drag", "scroll", "type", "hotkey", "wait"]
    x: int | None = None
    y: int | None = None
    duration: float = Field(default=0.2, ge=0, le=30)
    button: Literal["left", "middle", "right"] = "left"
    amount: int | None = None
    text: str | None = None
    keys: list[str] | None = None
    seconds: float | None = Field(default=None, ge=0, le=60)


class CommandRequest(BaseModel):
    command: str = Field(min_length=1, max_length=20_000)
    cwd: Path | None = None
    timeout_seconds: int | None = Field(default=None, ge=1, le=3600)
