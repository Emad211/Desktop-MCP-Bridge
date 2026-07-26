from __future__ import annotations

import shutil
from typing import Any

from ..security import require_capability, resolve_allowed_path


class PathOpsToolsMixin:

    def copy_path(self, source_path: str, destination_path: str, overwrite: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'source_path': source_path, 'destination_path': destination_path, 'overwrite': overwrite}

        def operation() -> dict[str, Any]:
            src = resolve_allowed_path(source_path, self.settings, must_exist=True)
            dst = resolve_allowed_path(destination_path, self.settings, must_exist=False)
            if dst.exists() and (not overwrite):
                raise FileExistsError(dst)
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=overwrite)
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
            return {'source': str(src), 'destination': str(dst)}
        return self._execute('copy_path', arguments, operation, source=source)

    def move_path(self, source_path: str, destination_path: str, overwrite: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'source_path': source_path, 'destination_path': destination_path, 'overwrite': overwrite}

        def operation() -> dict[str, Any]:
            src = resolve_allowed_path(source_path, self.settings, must_exist=True)
            dst = resolve_allowed_path(destination_path, self.settings, must_exist=False)
            if dst.exists():
                if not overwrite:
                    raise FileExistsError(dst)
                if dst.is_dir():
                    require_capability(self.settings, 'enable_recursive_delete')
                    shutil.rmtree(dst)
                else:
                    require_capability(self.settings, 'enable_delete')
                    dst.unlink()
            dst.parent.mkdir(parents=True, exist_ok=True)
            result = shutil.move(str(src), str(dst))
            return {'source': str(src), 'destination': result}
        return self._execute('move_path', arguments, operation, source=source)

    def delete_path(self, path: str, recursive: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'recursive': recursive}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_delete')
            target = resolve_allowed_path(path, self.settings, must_exist=True)
            if target.is_file() or target.is_symlink():
                target.unlink()
            elif recursive:
                require_capability(self.settings, 'enable_recursive_delete')
                shutil.rmtree(target)
            else:
                target.rmdir()
            return {'deleted': str(target), 'recursive': recursive}
        return self._execute('delete_path', arguments, operation, source=source)
