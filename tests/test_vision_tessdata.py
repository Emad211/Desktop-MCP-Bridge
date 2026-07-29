import os
from pathlib import Path

import pytest

from desktop_mcp_bridge.tools.vision import _configure_tessdata_environment


def test_tessdata_prefix_supports_windows_style_paths_with_spaces(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tessdata = tmp_path / "Emad Karimi" / "DesktopMCPBridge" / "tessdata"
    tessdata.mkdir(parents=True)
    (tessdata / "eng.traineddata").write_bytes(b"eng")
    (tessdata / "fas.traineddata").write_bytes(b"fas")
    monkeypatch.delenv("TESSDATA_PREFIX", raising=False)

    selected = _configure_tessdata_environment(tessdata, None, "eng+fas")

    assert selected == tessdata.resolve()
    assert os.environ["TESSDATA_PREFIX"].rstrip("\\/") == str(tessdata.resolve())
    assert '"' not in os.environ["TESSDATA_PREFIX"]


def test_tessdata_prefix_accepts_existing_environment_directory(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tessdata = tmp_path / "runtime tessdata"
    tessdata.mkdir()
    (tessdata / "eng.traineddata").write_bytes(b"eng")
    monkeypatch.setenv("TESSDATA_PREFIX", f'"{tessdata}"')

    selected = _configure_tessdata_environment(None, None, "eng")

    assert selected == tessdata.resolve()
    assert os.environ["TESSDATA_PREFIX"].rstrip("\\/") == str(tessdata.resolve())


def test_tessdata_prefix_reports_missing_requested_language(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tessdata = tmp_path / "tessdata"
    tessdata.mkdir()
    (tessdata / "eng.traineddata").write_bytes(b"eng")
    monkeypatch.delenv("TESSDATA_PREFIX", raising=False)

    with pytest.raises(RuntimeError, match="fas"):
        _configure_tessdata_environment(tessdata, None, "eng+fas")
