from typing import Any
from uuid import uuid4

from fastapi.testclient import TestClient

from desktop_mcp_bridge import action_api
from desktop_mcp_bridge.action_api import _add_artifact_urls, _dispatch


def test_dispatch_accepts_operation_alias() -> None:
    def callback(operation_name: str, *, source: str) -> dict[str, Any]:
        return {"operation_name": operation_name, "source": source}

    result = _dispatch("tool", {"operation": "status"}, {"tool": callback})
    assert result["ok"] is True
    assert result["result"]["operation_name"] == "status"
    assert result["result"]["source"] == "gpt-action"


def test_artifact_url_expansion() -> None:
    result = _add_artifact_urls(
        {"artifact": {"artifact_id": "abc", "token": "signed.token"}},
        "https://example.test/",
    )
    assert result["artifact"]["url"] == "https://example.test/v1/artifacts/signed.token"


def test_action_gateway_is_idempotent(monkeypatch: Any) -> None:
    monkeypatch.setattr(action_api.settings, "action_api_key", "k" * 40)
    monkeypatch.setattr(action_api.settings, "approval_policy", "autonomous")
    calls = {"count": 0}

    def callback(value: int, *, source: str) -> dict[str, Any]:
        calls["count"] += 1
        return {"value": value, "source": source}

    monkeypatch.setitem(action_api.WRITE_OPERATIONS, "clipboard_write", callback)
    client = TestClient(action_api.app)
    request_id = str(uuid4())
    body = {
        "operation": "clipboard_write",
        "arguments": {"value": 7},
        "request_id": request_id,
    }
    headers = {"Authorization": "Bearer " + "k" * 40}
    first = client.post("/v1/act", json=body, headers=headers)
    second = client.post("/v1/act", json=body, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    assert calls["count"] == 1
    assert second.json()["idempotent_replay"] is True


def test_guarded_start_job_requires_confirmation(monkeypatch: Any) -> None:
    monkeypatch.setattr(action_api.settings, "action_api_key", "g" * 40)
    monkeypatch.setattr(action_api.settings, "approval_policy", "guarded")

    def callback(command: str, *, source: str) -> dict[str, Any]:
        return {"command": command, "source": source}

    monkeypatch.setitem(action_api.WRITE_OPERATIONS, "start_command_job", callback)
    client = TestClient(action_api.app)
    body = {
        "operation": "start_command_job",
        "arguments": {"command": "echo ok"},
        "request_id": str(uuid4()),
    }
    headers = {"Authorization": "Bearer " + "g" * 40}
    rejected = client.post("/v1/act", json=body, headers=headers)
    assert rejected.status_code == 409
    body["request_id"] = str(uuid4())
    body["confirmation"] = "CONFIRM:start_command_job"
    accepted = client.post("/v1/act", json=body, headers=headers)
    assert accepted.status_code == 200


def test_public_health_does_not_expose_local_privileges() -> None:
    client = TestClient(action_api.app)
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert "administrator" not in payload
    assert "profile" not in payload
