from __future__ import annotations
import os
import subprocess
from pathlib import Path
from typing import Any
import psutil
from ..config import CommandRequest
from ..security import SecurityViolation, require_capability, require_full_access, resolve_allowed_path, validate_command

class ProcessToolsMixin:

    def run_command(self, command: str, cwd: str | None=None, timeout_seconds: int | None=None, environment: dict[str, str] | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'command': command, 'cwd': cwd, 'timeout_seconds': timeout_seconds, 'environment': environment or {}}

        def operation() -> dict[str, Any]:
            request = CommandRequest(command=command, cwd=Path(cwd) if cwd else None, timeout_seconds=timeout_seconds, environment=environment or {})
            validate_command(request.command, self.settings)
            base_cwd = request.cwd or (Path.cwd() if self.settings.is_full_access else self.settings.allowed_roots[0])
            working_dir = resolve_allowed_path(base_cwd, self.settings, must_exist=True)
            timeout = request.timeout_seconds or self.settings.command_timeout_seconds
            env = os.environ.copy()
            env.update(request.environment)
            completed = subprocess.run(request.command, cwd=working_dir, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout, check=False, env=env)
            cap = self.settings.command_output_bytes
            return {'command': request.command, 'cwd': str(working_dir), 'exit_code': completed.returncode, 'stdout': completed.stdout[-cap:], 'stderr': completed.stderr[-cap:], 'truncated': len(completed.stdout) > cap or len(completed.stderr) > cap}
        return self._execute('run_command', arguments, operation, source=source)

    def start_command_job(self, command: str, cwd: str | None=None, environment: dict[str, str] | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'command': command, 'cwd': cwd, 'environment': environment or {}}

        def operation() -> dict[str, Any]:
            validate_command(command, self.settings)
            base_cwd = Path(cwd) if cwd else Path.cwd() if self.settings.is_full_access else self.settings.allowed_roots[0]
            working_dir = resolve_allowed_path(base_cwd, self.settings, must_exist=True)
            return self.jobs.start(command, working_dir, environment=environment)
        return self._execute('start_command_job', arguments, operation, source=source)

    def get_command_job(self, job_id: str, tail_bytes: int=100000, *, source: str='local') -> dict[str, Any]:
        return self._execute('get_command_job', {'job_id': job_id, 'tail_bytes': tail_bytes}, lambda: self.jobs.status(job_id, tail_bytes), source=source)

    def list_command_jobs(self, limit: int=100, *, source: str='local') -> dict[str, Any]:
        return self._execute('list_command_jobs', {'limit': limit}, lambda: {'jobs': self.jobs.list(limit)}, source=source)

    def cancel_command_job(self, job_id: str, force: bool=False, *, source: str='local') -> dict[str, Any]:
        return self._execute('cancel_command_job', {'job_id': job_id, 'force': force}, lambda: self.jobs.cancel(job_id, force), source=source)

    def list_processes(self, limit: int=500, include_command_line: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'limit': limit, 'include_command_line': include_command_line}

        def operation() -> dict[str, Any]:
            attributes = ['pid', 'name', 'username', 'status', 'cpu_percent', 'memory_info']
            if include_command_line:
                require_full_access(self.settings, 'Process command-line inspection')
                attributes.append('cmdline')
            rows: list[dict[str, Any]] = []
            for process in psutil.process_iter(attributes):
                try:
                    info = dict(process.info)
                    memory = info.get('memory_info')
                    if memory is not None:
                        info['memory_rss'] = memory.rss
                        info.pop('memory_info', None)
                    rows.append(info)
                    if len(rows) >= max(1, min(limit, 5000)):
                        break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            return {'processes': rows, 'count': len(rows)}
        return self._execute('list_processes', arguments, operation, source=source)

    def stop_process(self, pid: int, force: bool=False, tree: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'pid': pid, 'force': force, 'tree': tree}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_process_control')
            if pid in {0, 4, os.getpid()}:
                raise SecurityViolation('Protected process')
            process = psutil.Process(pid)
            targets = process.children(recursive=True) + [process] if tree else [process]
            names = []
            for target in reversed(targets):
                names.append({'pid': target.pid, 'name': target.name()})
                target.kill() if force else target.terminate()
            _, alive = psutil.wait_procs(targets, timeout=10)
            return {'targets': names, 'force': force, 'alive': [item.pid for item in alive]}
        return self._execute('stop_process', arguments, operation, source=source)
