from pathlib import Path

import pytest

from desktop_mcp_bridge.config import FULL_ACCESS_CONFIRMATION, BridgeSettings
from desktop_mcp_bridge.security import SecurityViolation, validate_browser_url


def test_safe_browser_rejects_file_and_loopback(tmp_path: Path) -> None:
    settings = BridgeSettings(allowed_roots=[tmp_path])
    with pytest.raises(SecurityViolation):
        validate_browser_url("file:///C:/Windows/win.ini", settings)
    with pytest.raises(SecurityViolation):
        validate_browser_url("http://127.0.0.1:8766", settings)
    assert validate_browser_url("https://example.com", settings) == "https://example.com"


def test_full_browser_allows_local_resources(tmp_path: Path) -> None:
    settings = BridgeSettings(
        access_profile="full",
        full_access_confirmation=FULL_ACCESS_CONFIRMATION,
        allowed_roots=[tmp_path],
    )
    assert validate_browser_url("file:///C:/Windows/win.ini", settings).startswith("file:")
    assert validate_browser_url("http://127.0.0.1:8766", settings).startswith("http:")
