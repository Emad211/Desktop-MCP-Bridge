import json
from pathlib import Path

from desktop_mcp_bridge.config import BridgeSettings


def test_plain_string_allowed_root_environment_is_accepted(
    monkeypatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setenv("DMB_ALLOWED_ROOTS", str(tmp_path))

    settings = BridgeSettings()

    assert settings.allowed_roots == [tmp_path.resolve()]


def test_json_array_allowed_roots_environment_is_accepted(
    monkeypatch,
    tmp_path: Path,
) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    monkeypatch.setenv("DMB_ALLOWED_ROOTS", json.dumps([str(first), str(second)]))

    settings = BridgeSettings()

    assert settings.allowed_roots == [first.resolve(), second.resolve()]


def test_programmatic_single_path_is_normalized_to_a_list(tmp_path: Path) -> None:
    settings = BridgeSettings(allowed_roots=tmp_path)

    assert settings.allowed_roots == [tmp_path.resolve()]
