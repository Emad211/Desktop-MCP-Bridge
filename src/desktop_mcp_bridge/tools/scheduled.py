from __future__ import annotations
import os
import subprocess
from typing import Any
from ..security import require_capability

class ScheduledPowerToolsMixin:

    def scheduled_task_control(self, operation_name: str, task_name: str, command: str | None=None, schedule: str | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'operation': operation_name, 'task_name': task_name, 'command': command, 'schedule': schedule}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_scheduled_tasks')
            if os.name != 'nt':
                raise OSError('Scheduled tasks are only supported on Windows')
            op = operation_name.lower()
            if op == 'query':
                args = ['schtasks', '/Query', '/TN', task_name, '/V', '/FO', 'LIST']
            elif op == 'run':
                args = ['schtasks', '/Run', '/TN', task_name]
            elif op == 'end':
                args = ['schtasks', '/End', '/TN', task_name]
            elif op == 'delete':
                args = ['schtasks', '/Delete', '/TN', task_name, '/F']
            elif op == 'create':
                if not command or not schedule:
                    raise ValueError('create requires command and schedule')
                args = ['schtasks', '/Create', '/TN', task_name, '/TR', command, '/SC', schedule, '/F']
            else:
                raise ValueError('operation must be query|run|end|delete|create')
            completed = subprocess.run(args, capture_output=True, text=True, check=False, timeout=60)
            return {'exit_code': completed.returncode, 'output': completed.stdout + completed.stderr}
        return self._execute('scheduled_task_control', arguments, operation, source=source)

    def power_control(self, operation_name: str, delay_seconds: int=0, *, source: str='local') -> dict[str, Any]:
        arguments = {'operation': operation_name, 'delay_seconds': delay_seconds}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_power_control')
            if os.name != 'nt':
                raise OSError('Power control is only supported on Windows')
            op = operation_name.lower()
            delay = max(0, min(delay_seconds, 86400))
            if op == 'shutdown':
                args = ['shutdown', '/s', '/t', str(delay)]
            elif op == 'restart':
                args = ['shutdown', '/r', '/t', str(delay)]
            elif op == 'logoff':
                args = ['shutdown', '/l']
            elif op == 'abort':
                args = ['shutdown', '/a']
            elif op == 'lock':
                args = ['rundll32.exe', 'user32.dll,LockWorkStation']
            elif op == 'sleep':
                args = ['rundll32.exe', 'powrprof.dll,SetSuspendState', '0,1,0']
            else:
                raise ValueError('operation must be shutdown|restart|logoff|abort|lock|sleep')
            completed = subprocess.run(args, capture_output=True, text=True, check=False)
            return {'exit_code': completed.returncode, 'output': completed.stdout + completed.stderr}
        return self._execute('power_control', arguments, operation, source=source)
