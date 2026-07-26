from __future__ import annotations

import os
from pathlib import Path
from typing import Literal

from platformdirs import user_state_dir
from pydantic import BaseModel, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

FULL_ACCESS_CONFIRMATION = "I UNDERSTAND THIS GRANTS FULL CONTROL"


def _state_path(filename: str) -> Path:
    return Path(user_state_dir("DesktopMCPBridge", "Emad211")) / filename


class BridgeSettings(BaseSettings):
    """Runtime settings. Environment variables use the DMB_ prefix."""

    model_config = SettingsConfigDict(
        env_prefix="DMB_",
        env_nested_delimiter="__",
        case_sensitive=False,
        extra="ignore",
    )

    transport: Literal["stdio", "streamable-http", "sse"] = "stdio"
    host: str = "127.0.0.1"
    port: int = Field(default=8765, ge=1024, le=65535)
    action_host: str = "127.0.0.1"
    action_port: int = Field(default=8766, ge=1024, le=65535)
    action_api_key: str = ""
    action_rate_limit_per_minute: int = Field(default=120, ge=10, le=10_000)
    action_max_payload_chars: int = Field(default=90_000, ge=10_000, le=500_000)
    approval_policy: Literal["guarded", "autonomous"] = "guarded"
    idempotency_ttl_seconds: int = Field(default=900, ge=60, le=86_400)
    idempotency_path: Path = Field(default_factory=lambda: _state_path("idempotency.json"))

    access_profile: Literal["safe", "developer", "full"] = "safe"
    full_access_confirmation: str = ""
    allowed_roots: list[Path] = Field(default_factory=lambda: [Path.cwd()])

    max_read_bytes: int = Field(default=10_000_000, ge=1_024, le=500_000_000)
    max_write_bytes: int = Field(default=10_000_000, ge=1_024, le=500_000_000)
    command_timeout_seconds: int = Field(default=120, ge=1, le=3600)
    command_output_bytes: int = Field(default=500_000, ge=10_000, le=10_000_000)
    max_desktop_actions: int = Field(default=100, ge=1, le=500)

    enable_desktop_control: bool = True
    enable_shell: bool = True
    enable_process_control: bool = False
    enable_delete: bool = False
    enable_recursive_delete: bool = False
    enable_clipboard: bool = False
    enable_window_control: bool = True
    enable_ui_automation: bool = True
    enable_ocr: bool = True
    enable_browser: bool = True
    enable_registry: bool = False
    enable_service_control: bool = False
    enable_package_management: bool = False
    enable_network_admin: bool = False
    enable_scheduled_tasks: bool = False
    enable_power_control: bool = False
    allow_powershell: bool = True

    tesseract_command: str = ""
    tessdata_dir: Path | None = None
    browser_headless: bool = False

    audit_log_path: Path = Field(default_factory=lambda: _state_path("audit.jsonl"))
    kill_switch_path: Path = Field(default_factory=lambda: _state_path("STOP"))
    job_state_path: Path = Field(default_factory=lambda: _state_path("jobs"))
    artifact_path: Path = Field(default_factory=lambda: _state_path("artifacts"))
    artifact_signing_key: str = ""
    artifact_ttl_seconds: int = Field(default=300, ge=30, le=86_400)
    browser_profile_path: Path = Field(default_factory=lambda: _state_path("browser-profile"))
    browser_downloads_path: Path = Field(default_factory=lambda: _state_path("downloads"))

    allowed_executables: list[str] = Field(
        default_factory=lambda: [
            "cmd",
            "powershell",
            "pwsh",
            "python",
            "python3",
            "py",
            "git",
            "node",
            "npm",
            "npx",
            "pnpm",
            "yarn",
            "dotnet",
            "java",
            "javac",
            "gradle",
            "gradlew",
            "adb",
            "flutter",
            "dart",
            "winget",
        ]
    )
    blocked_command_fragments: list[str] = Field(
        default_factory=lambda: [
            "format ",
            "diskpart",
            "cipher /w",
            "bcdedit",
            "reg delete",
            "shutdown ",
            "restart-computer",
            "stop-computer",
            "remove-item -recurse",
            "rm -rf",
            "del /s",
            "rd /s",
            "rmdir /s",
            "net user",
            "net localgroup administrators",
        ]
    )

    @field_validator("allowed_roots", mode="after")
    @classmethod
    def normalize_roots(cls, roots: list[Path]) -> list[Path]:
        return [root.expanduser().resolve() for root in roots]

    @field_validator("tessdata_dir", mode="after")
    @classmethod
    def normalize_optional_path(cls, path: Path | None) -> Path | None:
        return None if path is None else path.expanduser().resolve()

    @field_validator(
        "audit_log_path",
        "kill_switch_path",
        "job_state_path",
        "artifact_path",
        "browser_profile_path",
        "browser_downloads_path",
        "idempotency_path",
        mode="after",
    )
    @classmethod
    def normalize_state_paths(cls, path: Path) -> Path:
        return path.expanduser().resolve()

    @model_validator(mode="after")
    def apply_profile_defaults(self) -> BridgeSettings:
        if self.access_profile == "developer":
            self.enable_delete = True
            self.enable_process_control = True
            self.enable_clipboard = True
        elif self.access_profile == "full":
            if self.full_access_confirmation != FULL_ACCESS_CONFIRMATION:
                raise ValueError(
                    "Full profile requires DMB_FULL_ACCESS_CONFIRMATION="
                    f"'{FULL_ACCESS_CONFIRMATION}'"
                )
            self.enable_delete = True
            self.enable_recursive_delete = True
            self.enable_process_control = True
            self.enable_clipboard = True
            self.enable_registry = True
            self.enable_service_control = True
            self.enable_package_management = True
            self.enable_network_admin = True
            self.enable_scheduled_tasks = True
            self.enable_power_control = True
        return self

    @property
    def is_full_access(self) -> bool:
        return (
            self.access_profile == "full"
            and self.full_access_confirmation == FULL_ACCESS_CONFIRMATION
        )

    @property
    def is_administrator(self) -> bool:
        if os.name != "nt":
            return os.geteuid() == 0 if hasattr(os, "geteuid") else False
        try:
            import ctypes

            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except (AttributeError, OSError):
            return False


class DesktopAction(BaseModel):
    type: Literal[
        "click",
        "double_click",
        "move",
        "drag",
        "scroll",
        "type",
        "hotkey",
        "press",
        "wait",
    ]
    x: int | None = None
    y: int | None = None
    duration: float = Field(default=0.2, ge=0, le=30)
    button: Literal["left", "middle", "right"] = "left"
    amount: int | None = None
    text: str | None = None
    keys: list[str] | None = None
    key: str | None = None
    presses: int = Field(default=1, ge=1, le=100)
    seconds: float | None = Field(default=None, ge=0, le=300)


class CommandRequest(BaseModel):
    command: str = Field(min_length=1, max_length=100_000)
    cwd: Path | None = None
    timeout_seconds: int | None = Field(default=None, ge=1, le=3600)
    environment: dict[str, str] = Field(default_factory=dict)
