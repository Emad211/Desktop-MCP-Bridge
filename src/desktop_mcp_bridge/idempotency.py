from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class CacheEntry:
    request_hash: str
    created_at: float
    result: dict[str, Any] | None = None
    in_progress: bool = True


class IdempotencyCache:
    """Prevents retries from executing a state change more than once.

    Completed responses are persisted atomically when a path is configured. In-progress entries are
    intentionally not restored after a process restart, because the original local operation can no
    longer be observed reliably by the new process.
    """

    def __init__(
        self,
        ttl_seconds: int = 900,
        max_entries: int = 2_000,
        path: Path | None = None,
    ) -> None:
        self.ttl_seconds = max(60, ttl_seconds)
        self.max_entries = max(100, max_entries)
        self.path = None if path is None else path.expanduser().resolve()
        self._entries: dict[str, CacheEntry] = {}
        self._lock = threading.RLock()
        self._load()

    @staticmethod
    def request_hash(operation: str, arguments: dict[str, Any]) -> str:
        payload = json.dumps(
            {"operation": operation, "arguments": arguments},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            default=str,
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def begin(self, request_id: str, request_hash: str) -> dict[str, Any] | None:
        now = time.time()
        with self._lock:
            changed = self._cleanup(now)
            existing = self._entries.get(request_id)
            if existing is None:
                self._entries[request_id] = CacheEntry(
                    request_hash=request_hash,
                    created_at=now,
                )
                if changed:
                    self._persist()
                return None
            if existing.request_hash != request_hash:
                raise ValueError("request_id was already used with different arguments")
            if existing.in_progress:
                raise RuntimeError("An identical request is still in progress")
            return existing.result

    def complete(self, request_id: str, result: dict[str, Any]) -> None:
        with self._lock:
            entry = self._entries.get(request_id)
            if entry is None:
                return
            entry.result = result
            entry.in_progress = False
            self._persist()

    def abandon(self, request_id: str) -> None:
        with self._lock:
            if self._entries.pop(request_id, None) is not None:
                self._persist()

    def _cleanup(self, now: float) -> bool:
        changed = False
        expired = [
            request_id
            for request_id, entry in self._entries.items()
            if now - entry.created_at > self.ttl_seconds
        ]
        for request_id in expired:
            self._entries.pop(request_id, None)
            changed = True
        if len(self._entries) <= self.max_entries:
            return changed
        oldest = sorted(self._entries.items(), key=lambda item: item[1].created_at)
        for request_id, _ in oldest[: len(self._entries) - self.max_entries]:
            self._entries.pop(request_id, None)
            changed = True
        return changed

    def _load(self) -> None:
        if self.path is None or not self.path.exists():
            return
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            now = time.time()
            for request_id, item in payload.get("entries", {}).items():
                created_at = float(item["created_at"])
                if now - created_at > self.ttl_seconds:
                    continue
                result = item.get("result")
                if not isinstance(result, dict):
                    continue
                self._entries[str(request_id)] = CacheEntry(
                    request_hash=str(item["request_hash"]),
                    created_at=created_at,
                    result=result,
                    in_progress=False,
                )
            self._cleanup(now)
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
            self._entries = {}

    def _persist(self) -> None:
        if self.path is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        completed = {
            request_id: {
                "request_hash": entry.request_hash,
                "created_at": entry.created_at,
                "result": entry.result,
            }
            for request_id, entry in self._entries.items()
            if not entry.in_progress and entry.result is not None
        }
        payload = {"version": 1, "entries": completed}
        temporary = self.path.with_name(
            f"{self.path.name}.{os.getpid()}.{threading.get_ident()}.tmp"
        )
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":"), default=str),
            encoding="utf-8",
        )
        os.replace(temporary, self.path)
