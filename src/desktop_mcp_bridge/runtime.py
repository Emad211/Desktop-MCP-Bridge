from __future__ import annotations

import json
import platform
from typing import Any, Callable, TypeVar

import psutil

from .audit import AuditLogger
from .config import BridgeSettings
from .jobs import JobManager
from .security import check_kill_switch
from .tools.input import InputToolsMixin
from .tools.screen import ScreenToolsMixin
from .tools.clipboard import ClipboardToolsMixin
from .tools.uia import UIAutomationToolsMixin
from .tools.windows import WindowToolsMixin
from .tools.file_read import FileReadToolsMixin
from .tools.file_write import FileWriteToolsMixin
from .tools.path_ops import PathOpsToolsMixin
from .tools.process import ProcessToolsMixin
from .tools.registry import RegistryToolsMixin
from .tools.network import NetworkToolsMixin
from .tools.scheduled import ScheduledPowerToolsMixin
from .tools.services import ServiceToolsMixin

T = TypeVar("T")

class DesktopBridge(
    ScreenToolsMixin,
    InputToolsMixin,
    ClipboardToolsMixin,
    WindowToolsMixin,
    UIAutomationToolsMixin,
    FileReadToolsMixin,
    FileWriteToolsMixin,
    PathOpsToolsMixin,
    ProcessToolsMixin,
    RegistryToolsMixin,
    ServiceToolsMixin,
    NetworkToolsMixin,
    ScheduledPowerToolsMixin,
):
    def __init__(self, settings: BridgeSettings | None=None) -> None:
        self.settings = settings or BridgeSettings()
        self.audit = AuditLogger(self.settings.audit_log_path)
        self.jobs = JobManager(self.settings.job_state_path, output_limit=self.settings.command_output_bytes)

    def _execute(self, action: str, arguments: dict[str, Any], operation: Callable[[], T], *, source: str='local') -> T:
        check_kill_switch(self.settings, action)
        try:
            result = operation()
            audit_result: Any = result
            if isinstance(result, (bytes, bytearray)):
                audit_result = {'bytes': len(result)}
            self.audit.write(action=action, arguments=arguments, ok=True, result=audit_result, source=source)
            return result
        except Exception as exc:
            self.audit.write(action=action, arguments=arguments, ok=False, error=f'{type(exc).__name__}: {exc}', source=source)
            raise

    def status(self, *, source: str='local') -> dict[str, Any]:
        settings = self.settings
        return {'version': '0.2.0', 'platform': platform.platform(), 'python': platform.python_version(), 'transport': settings.transport, 'access_profile': settings.access_profile, 'full_access_active': settings.is_full_access, 'administrator': settings.is_administrator, 'kill_switch_active': settings.kill_switch_path.exists(), 'kill_switch_path': str(settings.kill_switch_path), 'audit_log_path': str(settings.audit_log_path), 'allowed_roots': [str(path) for path in settings.allowed_roots], 'capabilities': {'desktop_control': settings.enable_desktop_control, 'shell': settings.enable_shell, 'process_control': settings.enable_process_control, 'delete': settings.enable_delete, 'recursive_delete': settings.enable_recursive_delete, 'clipboard': settings.enable_clipboard, 'window_control': settings.enable_window_control, 'ui_automation': settings.enable_ui_automation, 'registry': settings.enable_registry, 'service_control': settings.enable_service_control, 'package_management': settings.enable_package_management, 'network_admin': settings.enable_network_admin, 'scheduled_tasks': settings.enable_scheduled_tasks, 'power_control': settings.enable_power_control}}

    def system_info(self, *, source: str='local') -> dict[str, Any]:

        def operation() -> dict[str, Any]:
            memory = psutil.virtual_memory()
            disks = []
            for partition in psutil.disk_partitions(all=False):
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                except OSError:
                    continue
                disks.append({'device': partition.device, 'mountpoint': partition.mountpoint, 'fstype': partition.fstype, 'total': usage.total, 'used': usage.used, 'free': usage.free})
            return {'platform': platform.platform(), 'hostname': platform.node(), 'processor': platform.processor(), 'cpu_count': psutil.cpu_count(), 'boot_time': psutil.boot_time(), 'memory': {'total': memory.total, 'available': memory.available, 'used': memory.used, 'percent': memory.percent}, 'disks': disks, 'network_interfaces': list(psutil.net_if_addrs())}
        return self._execute('system_info', {}, operation, source=source)

    def audit_tail(self, limit: int=100, *, source: str='local') -> dict[str, Any]:
        return {'entries': self.audit.tail(limit)}

def json_result(payload: Any) -> str:
    return json.dumps({'ok': True, 'result': payload}, ensure_ascii=False, default=str)

def json_error(exc: Exception) -> str:
    return json.dumps({'ok': False, 'error': type(exc).__name__, 'message': str(exc)}, ensure_ascii=False)
