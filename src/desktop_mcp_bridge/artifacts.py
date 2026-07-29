from __future__ import annotations

import base64
import hashlib
import hmac
import json
import mimetypes
import os
import secrets
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Artifact:
    artifact_id: str
    path: Path
    filename: str
    mime_type: str
    created_at: float
    expires_at: float
    size: int


class ArtifactStore:
    """Short-lived local artifacts addressed by signed, unguessable tokens."""

    def __init__(self, root: Path, signing_key: str, ttl_seconds: int = 300) -> None:
        self.root = root.expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._key = signing_key.encode("utf-8")
        self.ttl_seconds = max(30, min(ttl_seconds, 86_400))
        self._lock = threading.RLock()
        self.cleanup()

    def create(
        self,
        data: bytes,
        *,
        filename: str,
        mime_type: str | None = None,
        ttl_seconds: int | None = None,
    ) -> dict[str, Any]:
        now = time.time()
        ttl = self.ttl_seconds if ttl_seconds is None else max(30, min(ttl_seconds, 86_400))
        safe_name = _safe_filename(filename)
        artifact_id = secrets.token_urlsafe(18)
        directory = self.root / artifact_id[:2]
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{artifact_id}-{safe_name}"
        path.write_bytes(data)
        expires_at = now + ttl
        metadata = {
            "artifact_id": artifact_id,
            "filename": safe_name,
            "mime_type": mime_type or mimetypes.guess_type(safe_name)[0] or "application/octet-stream",
            "created_at": now,
            "expires_at": expires_at,
            "size": len(data),
            "path": str(path),
        }
        path.with_suffix(path.suffix + ".json").write_text(
            json.dumps(metadata, ensure_ascii=False), encoding="utf-8"
        )
        token = self._sign({"id": artifact_id, "exp": int(expires_at)})
        self.cleanup()
        public_metadata = {key: value for key, value in metadata.items() if key != "path"}
        return {**public_metadata, "token": token}

    def resolve(self, token: str) -> Artifact:
        payload = self._verify(token)
        artifact_id = str(payload["id"])
        with self._lock:
            candidates = list(self.root.glob(f"{artifact_id[:2]}/{artifact_id}-*"))
            data_files = [path for path in candidates if not path.name.endswith(".json")]
            if len(data_files) != 1:
                raise FileNotFoundError("Artifact not found or expired")
            path = data_files[0]
            metadata_path = path.with_suffix(path.suffix + ".json")
            if metadata_path.exists():
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            else:
                stat = path.stat()
                metadata = {
                    "filename": path.name.split("-", 1)[-1],
                    "mime_type": mimetypes.guess_type(path.name)[0]
                    or "application/octet-stream",
                    "created_at": stat.st_ctime,
                    "expires_at": float(payload["exp"]),
                    "size": stat.st_size,
                }
            if time.time() > float(metadata["expires_at"]):
                self._delete(path)
                raise FileNotFoundError("Artifact expired")
            return Artifact(
                artifact_id=artifact_id,
                path=path,
                filename=str(metadata["filename"]),
                mime_type=str(metadata["mime_type"]),
                created_at=float(metadata["created_at"]),
                expires_at=float(metadata["expires_at"]),
                size=int(metadata["size"]),
            )

    def cleanup(self) -> int:
        removed = 0
        now = time.time()
        with self._lock:
            for metadata_path in self.root.glob("*/*.json"):
                try:
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                    if now <= float(metadata.get("expires_at", 0)):
                        continue
                    data_path = Path(str(metadata.get("path", "")))
                    if data_path.exists() and data_path.is_file():
                        data_path.unlink()
                    metadata_path.unlink(missing_ok=True)
                    removed += 1
                except (OSError, ValueError, TypeError, json.JSONDecodeError):
                    continue
        return removed

    def _sign(self, payload: dict[str, Any]) -> str:
        raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        encoded = _b64url(raw)
        signature = hmac.new(self._key, encoded.encode("ascii"), hashlib.sha256).digest()
        return f"{encoded}.{_b64url(signature)}"

    def _verify(self, token: str) -> dict[str, Any]:
        try:
            encoded, supplied_signature = token.split(".", 1)
            expected = hmac.new(
                self._key, encoded.encode("ascii"), hashlib.sha256
            ).digest()
            supplied = _b64url_decode(supplied_signature)
            if not hmac.compare_digest(expected, supplied):
                raise ValueError("Invalid artifact signature")
            payload = json.loads(_b64url_decode(encoded))
            if time.time() > float(payload["exp"]):
                raise ValueError("Artifact token expired")
            return payload
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            raise PermissionError("Invalid or expired artifact token") from exc

    @staticmethod
    def _delete(path: Path) -> None:
        try:
            path.unlink(missing_ok=True)
            path.with_suffix(path.suffix + ".json").unlink(missing_ok=True)
        except OSError:
            pass


def default_signing_key() -> str:
    return base64.urlsafe_b64encode(os.urandom(32)).decode("ascii")


def _safe_filename(value: str) -> str:
    cleaned = "".join(char if char.isalnum() or char in "._-" else "_" for char in value)
    cleaned = cleaned.strip("._")
    return cleaned[:120] or "artifact.bin"


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
