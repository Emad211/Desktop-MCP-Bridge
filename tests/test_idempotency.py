from pathlib import Path

import pytest

from desktop_mcp_bridge.idempotency import IdempotencyCache


def test_completed_response_survives_restart(tmp_path: Path) -> None:
    path = tmp_path / "idempotency.json"
    first = IdempotencyCache(path=path)
    request_hash = first.request_hash("write_text_file", {"path": "x", "content": "a"})
    assert first.begin("request-123", request_hash) is None
    first.complete("request-123", {"ok": True, "result": {"written": 1}})

    second = IdempotencyCache(path=path)
    assert second.begin("request-123", request_hash) == {
        "ok": True,
        "result": {"written": 1},
    }


def test_request_id_cannot_be_reused_for_other_arguments(tmp_path: Path) -> None:
    cache = IdempotencyCache(path=tmp_path / "cache.json")
    first_hash = cache.request_hash("tool", {"value": 1})
    second_hash = cache.request_hash("tool", {"value": 2})
    cache.begin("request-456", first_hash)
    cache.complete("request-456", {"ok": True})
    with pytest.raises(ValueError):
        cache.begin("request-456", second_hash)


def test_in_progress_entry_is_not_restored_after_restart(tmp_path: Path) -> None:
    path = tmp_path / "cache.json"
    cache = IdempotencyCache(path=path)
    request_hash = cache.request_hash("tool", {})
    cache.begin("request-789", request_hash)

    restarted = IdempotencyCache(path=path)
    assert restarted.begin("request-789", request_hash) is None
