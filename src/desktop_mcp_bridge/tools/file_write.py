from __future__ import annotations
import base64
from typing import Any
from ..security import resolve_allowed_path

class FileWriteToolsMixin:

    def write_text_file(self, path: str, content: str, overwrite: bool=False, create_parents: bool=False, encoding: str='utf-8', *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'content_bytes': len(content.encode(encoding, errors='replace')), 'overwrite': overwrite, 'create_parents': create_parents, 'encoding': encoding}

        def operation() -> dict[str, Any]:
            payload = content.encode(encoding)
            if len(payload) > self.settings.max_write_bytes:
                raise ValueError(f'Content exceeds max_write_bytes={self.settings.max_write_bytes}')
            file_path = resolve_allowed_path(path, self.settings, must_exist=False)
            if file_path.exists() and (not overwrite):
                raise FileExistsError('File exists; set overwrite=true to replace it')
            if create_parents:
                file_path.parent.mkdir(parents=True, exist_ok=True)
            elif not file_path.parent.exists():
                raise FileNotFoundError(f'Parent directory does not exist: {file_path.parent}')
            file_path.write_bytes(payload)
            return {'path': str(file_path), 'bytes_written': len(payload)}
        return self._execute('write_text_file', arguments, operation, source=source)

    def write_binary_file(self, path: str, content_base64: str, overwrite: bool=False, create_parents: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'base64_chars': len(content_base64), 'overwrite': overwrite, 'create_parents': create_parents}

        def operation() -> dict[str, Any]:
            data = base64.b64decode(content_base64, validate=True)
            if len(data) > self.settings.max_write_bytes:
                raise ValueError(f'Content exceeds max_write_bytes={self.settings.max_write_bytes}')
            file_path = resolve_allowed_path(path, self.settings, must_exist=False)
            if file_path.exists() and (not overwrite):
                raise FileExistsError('File exists; set overwrite=true to replace it')
            if create_parents:
                file_path.parent.mkdir(parents=True, exist_ok=True)
            elif not file_path.parent.exists():
                raise FileNotFoundError(f'Parent directory does not exist: {file_path.parent}')
            file_path.write_bytes(data)
            return {'path': str(file_path), 'bytes_written': len(data)}
        return self._execute('write_binary_file', arguments, operation, source=source)
