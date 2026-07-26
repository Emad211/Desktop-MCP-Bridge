from __future__ import annotations
import os
import subprocess
from typing import Any
from ..security import require_capability

class NetworkToolsMixin:

    def network_admin(self, operation_name: str, target: str | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'operation': operation_name, 'target': target}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_network_admin')
            if os.name != 'nt':
                raise OSError('Network administration is only supported on Windows')
            op = operation_name.lower()
            commands = {'ipconfig': ['ipconfig', '/all'], 'flush_dns': ['ipconfig', '/flushdns'], 'routes': ['route', 'print'], 'connections': ['netstat', '-ano'], 'ping': ['ping', '-n', '4', target or '127.0.0.1'], 'dns_lookup': ['nslookup', target or 'localhost']}
            if op not in commands:
                raise ValueError('operation must be ipconfig|flush_dns|routes|connections|ping|dns_lookup')
            completed = subprocess.run(commands[op], capture_output=True, text=True, check=False, timeout=60)
            return {'exit_code': completed.returncode, 'output': completed.stdout + completed.stderr}
        return self._execute('network_admin', arguments, operation, source=source)
