from pathlib import Path

import pytest

from desktop_mcp_bridge.artifacts import ArtifactStore


def test_signed_artifact_round_trip_hides_local_path(tmp_path: Path) -> None:
    store = ArtifactStore(tmp_path, "a" * 32, ttl_seconds=60)
    public = store.create(b"hello", filename="hello.txt", mime_type="text/plain")
    assert "path" not in public
    artifact = store.resolve(public["token"])
    assert artifact.path.read_bytes() == b"hello"
    assert artifact.filename == "hello.txt"


def test_tampered_artifact_token_is_rejected(tmp_path: Path) -> None:
    store = ArtifactStore(tmp_path, "b" * 32, ttl_seconds=60)
    public = store.create(b"hello", filename="hello.txt")
    with pytest.raises(PermissionError):
        store.resolve(public["token"] + "x")
