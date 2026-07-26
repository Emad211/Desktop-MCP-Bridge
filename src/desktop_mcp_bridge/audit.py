from __future__ import annotations

import json
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .security import redact


class AuditLogger:
    """Append-only JSONL audit log with basic secret redaction."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.Lock()

    def write(
        self,
        *,
        action: str,
        arguments: dict[str, Any],
        ok: bool,
        result: Any = None,
        error: str | None = None,
        source: str = "local",
    ) -> None:
        entry = {
            "timestamp": datetime.now(UTC).isoformat(),
            "source": source,
            "action": action,
            "arguments": redact(arguments),
            "ok": ok,
            "result": redact(result),
            "error": error,
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps(entry, ensure_ascii=False, default=str) + "\n"
        with self._lock, self.path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(line)

    def tail(self, limit: int = 100) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        lines = self.path.read_text(encoding="utf-8", errors="replace").splitlines()
        rows: list[dict[str, Any]] = []
        for line in lines[-max(1, min(limit, 1000)) :]:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                rows.append({"malformed": line})
        return rows
