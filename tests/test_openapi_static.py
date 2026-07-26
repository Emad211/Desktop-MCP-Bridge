from pathlib import Path
from typing import get_args

import yaml

from desktop_mcp_bridge.action_api import ReadOperation, WriteOperation, app


def test_static_openapi_operations_match_gateway() -> None:
    path = Path(__file__).resolve().parents[1] / "gpt-actions.openapi.yaml"
    schema = yaml.safe_load(path.read_text(encoding="utf-8"))
    observe = schema["components"]["schemas"]["ObserveRequest"]["properties"]["operation"]["enum"]
    actions = schema["components"]["schemas"]["ActRequest"]["properties"]["operation"]["enum"]
    assert set(observe) == set(get_args(ReadOperation))
    assert set(actions) == set(get_args(WriteOperation))
    assert schema["openapi"].startswith("3.1")


def test_generated_openapi_exposes_artifacts_and_screenshot() -> None:
    schema = app.openapi()
    assert "/v1/screenshot" in schema["paths"]
    assert "/v1/observe" in schema["paths"]
    assert "/v1/act" in schema["paths"]
    assert schema["info"]["version"] == "1.1.0"
