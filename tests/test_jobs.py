import sys
import time
from pathlib import Path

from desktop_mcp_bridge.jobs import JobManager


def test_command_job_completes_and_returns_logs(tmp_path: Path) -> None:
    manager = JobManager(tmp_path / "jobs")
    command = f'"{sys.executable}" -c "print(12345)"'
    started = manager.start(command=command, cwd=tmp_path, environment={})
    job_id = started["id"]

    deadline = time.monotonic() + 10
    status = manager.status(job_id)
    while status["status"] in {"starting", "running"} and time.monotonic() < deadline:
        time.sleep(0.05)
        status = manager.status(job_id)

    assert status["status"] == "completed"
    assert status["exit_code"] == 0
    assert "12345" in (status["stdout"] + status["stderr"])
