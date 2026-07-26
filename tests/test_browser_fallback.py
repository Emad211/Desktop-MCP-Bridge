from pathlib import Path

from desktop_mcp_bridge.config import BridgeSettings
from desktop_mcp_bridge.tools.browser import _launch_candidates


def test_auto_browser_candidates_try_managed_then_system_channels() -> None:
    candidates = _launch_candidates("auto", None)
    labels = [candidate["label"] for candidate in candidates]
    assert labels[:3] == [
        "playwright-chromium",
        "channel-msedge",
        "channel-chrome",
    ]


def test_explicit_browser_path_is_first(tmp_path: Path) -> None:
    executable = tmp_path / "browser.exe"
    executable.write_bytes(b"")
    candidates = _launch_candidates("chrome", executable)
    assert candidates[0]["label"] == "configured-executable"
    assert candidates[0]["executable_path"] == str(executable)
    assert candidates[1]["label"] == "channel-chrome"


def test_browser_settings_accept_channel_and_executable(tmp_path: Path) -> None:
    executable = tmp_path / "msedge.exe"
    settings = BridgeSettings(
        allowed_roots=[tmp_path],
        browser_channel="msedge",
        browser_executable_path=executable,
    )
    assert settings.browser_channel == "msedge"
    assert settings.browser_executable_path == executable.resolve()
