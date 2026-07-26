from __future__ import annotations
import base64
import os
from typing import Any
from ..security import require_capability

class RegistryToolsMixin:

    def registry_get(self, hive: str, key: str, value_name: str='', *, source: str='local') -> dict[str, Any]:
        arguments = {'hive': hive, 'key': key, 'value_name': value_name}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_registry')
            if os.name != 'nt':
                raise OSError('Registry is only available on Windows')
            import winreg
            root = _registry_hive(winreg, hive)
            with winreg.OpenKey(root, key, 0, winreg.KEY_READ) as handle:
                value, value_type = winreg.QueryValueEx(handle, value_name)
            return {'hive': hive, 'key': key, 'value_name': value_name, 'value': value, 'type': value_type}
        return self._execute('registry_get', arguments, operation, source=source)

    def registry_set(self, hive: str, key: str, value_name: str, value: Any, value_type: str='string', *, source: str='local') -> dict[str, Any]:
        arguments = {'hive': hive, 'key': key, 'value_name': value_name, 'value': value, 'value_type': value_type}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_registry')
            if os.name != 'nt':
                raise OSError('Registry is only available on Windows')
            import winreg
            root = _registry_hive(winreg, hive)
            type_map = {'string': winreg.REG_SZ, 'expand_string': winreg.REG_EXPAND_SZ, 'dword': winreg.REG_DWORD, 'qword': winreg.REG_QWORD, 'multi_string': winreg.REG_MULTI_SZ, 'binary': winreg.REG_BINARY}
            if value_type not in type_map:
                raise ValueError(f'Unsupported registry type: {value_type}')
            converted_value = value
            if value_type == 'binary' and isinstance(converted_value, str):
                converted_value = base64.b64decode(converted_value)
            with winreg.CreateKeyEx(root, key, 0, winreg.KEY_SET_VALUE) as handle:
                winreg.SetValueEx(handle, value_name, 0, type_map[value_type], converted_value)
            return {'hive': hive, 'key': key, 'value_name': value_name, 'updated': True}
        return self._execute('registry_set', arguments, operation, source=source)

    def registry_delete(self, hive: str, key: str, value_name: str | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'hive': hive, 'key': key, 'value_name': value_name}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_registry')
            if os.name != 'nt':
                raise OSError('Registry is only available on Windows')
            import winreg
            root = _registry_hive(winreg, hive)
            if value_name is None:
                winreg.DeleteKey(root, key)
            else:
                with winreg.OpenKey(root, key, 0, winreg.KEY_SET_VALUE) as handle:
                    winreg.DeleteValue(handle, value_name)
            return {'hive': hive, 'key': key, 'value_name': value_name, 'deleted': True}
        return self._execute('registry_delete', arguments, operation, source=source)

def _registry_hive(winreg: Any, name: str) -> Any:
    aliases = {'HKCU': winreg.HKEY_CURRENT_USER, 'HKEY_CURRENT_USER': winreg.HKEY_CURRENT_USER, 'HKLM': winreg.HKEY_LOCAL_MACHINE, 'HKEY_LOCAL_MACHINE': winreg.HKEY_LOCAL_MACHINE, 'HKCR': winreg.HKEY_CLASSES_ROOT, 'HKEY_CLASSES_ROOT': winreg.HKEY_CLASSES_ROOT, 'HKU': winreg.HKEY_USERS, 'HKEY_USERS': winreg.HKEY_USERS, 'HKCC': winreg.HKEY_CURRENT_CONFIG, 'HKEY_CURRENT_CONFIG': winreg.HKEY_CURRENT_CONFIG}
    try:
        return aliases[name.upper()]
    except KeyError as exc:
        raise ValueError(f'Unsupported registry hive: {name}') from exc
