from desktop_mcp_bridge.server import mcp
from desktop_mcp_bridge.superassistant_server import apply_superassistant_compatibility


def test_superassistant_compatibility_disables_output_schemas() -> None:
    summary = apply_superassistant_compatibility(mcp)

    assert summary["registered_tools"] >= 20
    assert summary["modified_tools"] == summary["registered_tools"]
    assert "bridge_status" in summary["tool_names"]
    assert "run_command" in summary["tool_names"]
    assert "browser_snapshot" in summary["tool_names"]

    manager = getattr(mcp, "_tool_manager")
    for tool in manager.list_tools():
        metadata = getattr(tool, "fn_metadata", None)
        assert metadata is not None
        assert getattr(metadata, "output_schema", None) is None
        assert getattr(metadata, "wrap_output", False) is False
