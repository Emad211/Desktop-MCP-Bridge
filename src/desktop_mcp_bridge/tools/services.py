from __future__ import annotations

import os
import subprocess
from typing import Any

from ..security import require_capability


class ServiceToolsMixin:

    def service_control(self, service_name: str, operation_name: str, *, source: str='local') -> dict[str, Any]:
        arguments = {'service_name': service_name, 'operation': operation_name}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_service_control')
            if os.name != 'nt':
                raise OSError('Service control is only supported on Windows')
            action = operation_name.lower()
            if action == 'status':
                command = ['sc.exe', 'query', service_name]
            elif action in {'start', 'stop', 'pause', 'continue'}:
                command = ['sc.exe', action, service_name]
            elif action == 'restart':
                stop = subprocess.run(['sc.exe', 'stop', service_name], capture_output=True, text=True, check=False)
                start = subprocess.run(['sc.exe', 'start', service_name], capture_output=True, text=True, check=False)
                return {'stop_exit_code': stop.returncode, 'stop_output': stop.stdout + stop.stderr, 'start_exit_code': start.returncode, 'start_output': start.stdout + start.stderr}
            else:
                raise ValueError('operation must be status|start|stop|pause|continue|restart')
            completed = subprocess.run(command, capture_output=True, text=True, check=False)
            return {'exit_code': completed.returncode, 'output': completed.stdout + completed.stderr}
        return self._execute('service_control', arguments, operation, source=source)

    def package_manage(self, manager: str, operation_name: str, package: str, extra_args: list[str] | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'manager': manager, 'operation': operation_name, 'package': package, 'extra_args': extra_args or []}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_package_management')
            manager_name = manager.lower()
            op = operation_name.lower()
            if manager_name == 'winget':
                mapping = {'install': 'install', 'upgrade': 'upgrade', 'uninstall': 'uninstall', 'search': 'search'}
                if op not in mapping:
                    raise ValueError('Unsupported winget operation')
                command = ['winget', mapping[op], '--id' if op != 'search' else '--query', package]
                if op in {'install', 'upgrade', 'uninstall'}:
                    command += ['--accept-source-agreements', '--accept-package-agreements', '--silent']
            elif manager_name in {'choco', 'scoop'}:
                if op not in {'install', 'upgrade', 'uninstall', 'search'}:
                    raise ValueError('Unsupported package operation')
                command = [manager_name, op, package]
                if manager_name == 'choco' and op != 'search':
                    command.append('-y')
            else:
                raise ValueError('manager must be winget|choco|scoop')
            command += extra_args or []
            completed = subprocess.run(command, capture_output=True, text=True, check=False, timeout=1800)
            cap = self.settings.command_output_bytes
            return {'command': command, 'exit_code': completed.returncode, 'stdout': completed.stdout[-cap:], 'stderr': completed.stderr[-cap:]}
        return self._execute('package_manage', arguments, operation, source=source)
