import os
from pathlib import Path

from desktop_mcp_bridge.config import BridgeSettings
from desktop_mcp_bridge.runtime import DesktopBridge


def test_status_exposes_current_gateway_process_identity(tmp_path: Path) -> None:
    settings = BridgeSettings(
        allowed_roots=[tmp_path],
        enable_browser=False,
        audit_log_path=tmp_path / "audit.jsonl",
        kill_switch_path=tmp_path / "STOP",
        job_state_path=tmp_path / "jobs",
        artifact_path=tmp_path / "artifacts",
        browser_profile_path=tmp_path / "browser-profile",
        browser_downloads_path=tmp_path / "downloads",
        idempotency_path=tmp_path / "idempotency.json",
    )
    bridge = DesktopBridge(settings)
    try:
        status = bridge.status()
        assert status["process_id"] == os.getpid()
        assert status["process_started_at"] > 0
        assert isinstance(status["administrator"], bool)
    finally:
        bridge.close()
