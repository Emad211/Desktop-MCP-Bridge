from __future__ import annotations
import os
from typing import Any
from ..security import require_capability

class WindowToolsMixin:

    def list_windows(self, *, source: str='local') -> dict[str, Any]:

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_window_control')
            if os.name != 'nt':
                raise OSError('Window enumeration is only supported on Windows')
            import pygetwindow as gw
            rows = []
            for window in gw.getAllWindows():
                if not window.title:
                    continue
                rows.append({'title': window.title, 'left': window.left, 'top': window.top, 'width': window.width, 'height': window.height, 'active': window.isActive, 'minimized': window.isMinimized, 'maximized': window.isMaximized})
            return {'windows': rows, 'count': len(rows)}
        return self._execute('list_windows', {}, operation, source=source)

    def window_control(self, title: str, operation_name: str, *, source: str='local') -> dict[str, Any]:
        arguments = {'title': title, 'operation': operation_name}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_window_control')
            if os.name != 'nt':
                raise OSError('Window control is only supported on Windows')
            import pygetwindow as gw
            matches = gw.getWindowsWithTitle(title)
            if not matches:
                raise LookupError(f'No window matching title: {title}')
            window = matches[0]
            action = operation_name.lower()
            if action == 'activate':
                window.activate()
            elif action == 'minimize':
                window.minimize()
            elif action == 'maximize':
                window.maximize()
            elif action == 'restore':
                window.restore()
            elif action == 'close':
                window.close()
            else:
                raise ValueError('operation must be activate|minimize|maximize|restore|close')
            return {'title': window.title, 'operation': action}
        return self._execute('window_control', arguments, operation, source=source)
