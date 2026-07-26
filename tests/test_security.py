from pathlib import Path

import pytest

from desktop_mcp_bridge.config import BridgeSettings
from desktop_mcp_bridge.security import SecurityViolation, resolve_allowed_path, validate_command


def settings_for(root: Path) -> BridgeSettings:
    return BridgeSettings(allowed_roots=[root], allowed_executables=["python", "git"])


def test_path_inside_root_is_allowed(tmp_path: Path) -> None:
    target = tmp_path / "file.txt"
    target.write_text("ok", encoding="utf-8")
    assert resolve_allowed_path(target, settings_for(tmp_path), must_exist=True) == target.resolve()


def test_path_outside_root_is_rejected(tmp_path: Path) -> None:
    root = tmp_path / "root"
    root.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("no", encoding="utf-8")
    with pytest.raises(SecurityViolation):
        resolve_allowed_path(outside, settings_for(root), must_exist=True)


def test_allowlisted_command_is_allowed(tmp_path: Path) -> None:
    validate_command("python --version", settings_for(tmp_path))


def test_non_allowlisted_command_is_rejected(tmp_path: Path) -> None:
    with pytest.raises(SecurityViolation):
        validate_command("curl https://example.com", settings_for(tmp_path))


def test_blocked_fragment_wins(tmp_path: Path) -> None:
    config = settings_for(tmp_path)
    config.allowed_executables.append("shutdown")
    with pytest.raises(SecurityViolation):
        validate_command("shutdown /s", config)
