from pathlib import Path
from typing import Any, Callable

import pytest

from desktop_mcp_bridge.config import BridgeSettings
from desktop_mcp_bridge.security import SecurityViolation
from desktop_mcp_bridge.tools.browser import BrowserToolsMixin


class FakeBrowser:
    def submit(self, operation: str, **kwargs: Any) -> dict[str, Any]:
        return {"operation": operation, **kwargs}


class Harness(BrowserToolsMixin):
    def __init__(self, settings: BridgeSettings) -> None:
        self.settings = settings
        self.browser = FakeBrowser()

    def _execute(
        self,
        action: str,
        arguments: dict[str, Any],
        operation: Callable[[], dict[str, Any]],
        *,
        source: str,
    ) -> dict[str, Any]:
        return operation()


def test_browser_capability_is_enforced(tmp_path: Path) -> None:
    settings = BridgeSettings(allowed_roots=[tmp_path], enable_browser=False)
    with pytest.raises(SecurityViolation):
        Harness(settings).browser_status()


def test_browser_status_uses_worker_when_enabled(tmp_path: Path) -> None:
    settings = BridgeSettings(allowed_roots=[tmp_path], enable_browser=True)
    assert Harness(settings).browser_status()["operation"] == "status"
