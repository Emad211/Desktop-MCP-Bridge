from typing import Any

from desktop_mcp_bridge.action_api import _dispatch


def test_dispatch_accepts_operation_alias() -> None:
    def callback(operation_name: str, *, source: str) -> dict[str, Any]:
        return {"operation_name": operation_name, "source": source}

    result = _dispatch("tool", {"operation": "status"}, {"tool": callback})
    assert result["ok"] is True
    assert result["result"]["operation_name"] == "status"
    assert result["result"]["source"] == "gpt-action"
