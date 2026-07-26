import json
from pathlib import Path

from desktop_mcp_bridge.audit import AuditLogger


def test_audit_redacts_secret_fields(tmp_path: Path) -> None:
    path = tmp_path / "audit.jsonl"
    audit = AuditLogger(path)
    audit.write(
        action="test",
        arguments={"password": "secret", "nested": {"api_key": "abc", "safe": "ok"}},
        ok=True,
        result={"token": "hidden", "value": 3},
        source="pytest",
    )
    row = json.loads(path.read_text(encoding="utf-8"))
    assert row["arguments"]["password"] == "***REDACTED***"
    assert row["arguments"]["nested"]["api_key"] == "***REDACTED***"
    assert row["arguments"]["nested"]["safe"] == "ok"
    assert row["result"]["token"] == "***REDACTED***"


def test_audit_redacts_secrets_embedded_in_strings(tmp_path: Path) -> None:
    path = tmp_path / "audit.jsonl"
    audit = AuditLogger(path)
    audit.write(
        action="command",
        arguments={"command": "tool --token top-secret --password hunter2"},
        ok=True,
        source="pytest",
    )
    text = path.read_text(encoding="utf-8")
    assert "top-secret" not in text
    assert "hunter2" not in text
    assert "***REDACTED***" in text
