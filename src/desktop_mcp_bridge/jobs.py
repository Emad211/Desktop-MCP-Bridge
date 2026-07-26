from __future__ import annotations

import os
import signal
import subprocess
import threading
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


@dataclass
class CommandJob:
    id: str
    command: str
    cwd: str
    pid: int
    created_at: str
    stdout_path: str
    stderr_path: str
    status: str = "running"
    exit_code: int | None = None
    finished_at: str | None = None
    process: subprocess.Popen[bytes] = field(repr=False, compare=False, default=None)  # type: ignore[assignment]

    def public(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "command": self.command,
            "cwd": self.cwd,
            "pid": self.pid,
            "created_at": self.created_at,
            "stdout_path": self.stdout_path,
            "stderr_path": self.stderr_path,
            "status": self.status,
            "exit_code": self.exit_code,
            "finished_at": self.finished_at,
        }


class JobManager:
    """Manage long-running local shell commands without blocking an action call."""

    def __init__(self, state_path: Path, output_limit: int = 500_000) -> None:
        self.state_path = state_path
        self.output_limit = output_limit
        self._jobs: dict[str, CommandJob] = {}
        self._lock = threading.RLock()
        self.state_path.mkdir(parents=True, exist_ok=True)

    def start(
        self,
        command: str,
        cwd: Path,
        *,
        environment: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        job_id = uuid.uuid4().hex
        job_dir = self.state_path / job_id
        job_dir.mkdir(parents=True, exist_ok=False)
        stdout_path = job_dir / "stdout.log"
        stderr_path = job_dir / "stderr.log"
        stdout_handle = stdout_path.open("wb")
        stderr_handle = stderr_path.open("wb")
        env = os.environ.copy()
        env.update(environment or {})
        creationflags = 0
        start_new_session = os.name != "nt"
        if os.name == "nt":
            creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        try:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                shell=True,
                stdout=stdout_handle,
                stderr=stderr_handle,
                env=env,
                creationflags=creationflags,
                start_new_session=start_new_session,
            )
        finally:
            stdout_handle.close()
            stderr_handle.close()

        job = CommandJob(
            id=job_id,
            command=command,
            cwd=str(cwd),
            pid=process.pid,
            created_at=datetime.now(UTC).isoformat(),
            stdout_path=str(stdout_path),
            stderr_path=str(stderr_path),
            process=process,
        )
        with self._lock:
            self._jobs[job_id] = job
        return self.status(job_id)

    def _refresh(self, job: CommandJob) -> None:
        if job.status != "running":
            return
        code = job.process.poll()
        if code is not None:
            job.exit_code = code
            job.status = "completed" if code == 0 else "failed"
            job.finished_at = datetime.now(UTC).isoformat()

    def status(self, job_id: str, tail_bytes: int = 100_000) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                raise KeyError(f"Unknown job: {job_id}")
            self._refresh(job)
            data = job.public()
        limit = max(1, min(tail_bytes, self.output_limit))
        data["stdout"] = _read_tail(Path(job.stdout_path), limit)
        data["stderr"] = _read_tail(Path(job.stderr_path), limit)
        return data

    def list(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock:
            jobs = list(self._jobs.values())[-max(1, min(limit, 1000)) :]
            for job in jobs:
                self._refresh(job)
            return [job.public() for job in reversed(jobs)]

    def cancel(self, job_id: str, force: bool = False) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                raise KeyError(f"Unknown job: {job_id}")
            self._refresh(job)
            if job.status != "running":
                return self.status(job_id)
            if os.name == "nt":
                if force:
                    subprocess.run(
                        ["taskkill", "/PID", str(job.pid), "/T", "/F"],
                        capture_output=True,
                        check=False,
                    )
                else:
                    job.process.send_signal(getattr(signal, "CTRL_BREAK_EVENT", signal.SIGTERM))
            elif force:
                os.killpg(os.getpgid(job.pid), signal.SIGKILL)
            else:
                os.killpg(os.getpgid(job.pid), signal.SIGTERM)
            try:
                job.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                job.process.kill()
                job.process.wait(timeout=5)
            job.exit_code = job.process.returncode
            job.status = "cancelled"
            job.finished_at = datetime.now(UTC).isoformat()
            return self.status(job_id)


def _read_tail(path: Path, limit: int) -> str:
    if not path.exists():
        return ""
    size = path.stat().st_size
    with path.open("rb") as handle:
        if size > limit:
            handle.seek(-limit, os.SEEK_END)
        data = handle.read()
    return data.decode("utf-8", errors="replace")
