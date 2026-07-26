from __future__ import annotations

import base64
from typing import Any

from ..security import resolve_allowed_path


class FileReadToolsMixin:

    def list_directory(self, path: str='.', recursive: bool=False, limit: int=500, *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'recursive': recursive, 'limit': limit}

        def operation() -> dict[str, Any]:
            directory = resolve_allowed_path(path, self.settings, must_exist=True)
            if not directory.is_dir():
                raise NotADirectoryError(directory)
            iterator = directory.rglob('*') if recursive else directory.iterdir()
            entries: list[dict[str, Any]] = []
            cap = max(1, min(limit, 20000))
            for index, item in enumerate(iterator):
                if index >= cap:
                    break
                try:
                    stat = item.stat()
                except OSError:
                    continue
                entries.append({'path': str(item if self.settings.is_full_access else item.relative_to(directory)), 'type': 'directory' if item.is_dir() else 'file', 'size': stat.st_size, 'modified': stat.st_mtime, 'hidden': item.name.startswith('.')})
            return {'directory': str(directory), 'entries': entries, 'count': len(entries)}
        return self._execute('list_directory', arguments, operation, source=source)

    def read_text_file(self, path: str, start_line: int=1, end_line: int | None=None, encoding: str='utf-8', *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'start_line': start_line, 'end_line': end_line, 'encoding': encoding}

        def operation() -> dict[str, Any]:
            file_path = resolve_allowed_path(path, self.settings, must_exist=True)
            size = file_path.stat().st_size
            if size > self.settings.max_read_bytes:
                raise ValueError(f'File exceeds max_read_bytes={self.settings.max_read_bytes}')
            text = file_path.read_text(encoding=encoding, errors='replace')
            lines = text.splitlines()
            start = max(1, start_line)
            stop = len(lines) if end_line is None else min(len(lines), max(start, end_line))
            return {'path': str(file_path), 'size': size, 'start_line': start, 'end_line': stop, 'content': '\n'.join(lines[start - 1:stop])}
        return self._execute('read_text_file', arguments, operation, source=source)

    def read_binary_file(self, path: str, offset: int=0, length: int | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'path': path, 'offset': offset, 'length': length}

        def operation() -> dict[str, Any]:
            file_path = resolve_allowed_path(path, self.settings, must_exist=True)
            size = file_path.stat().st_size
            requested = min(length if length is not None else size - offset, self.settings.max_read_bytes)
            if offset < 0 or requested < 0:
                raise ValueError('offset and length must be non-negative')
            with file_path.open('rb') as handle:
                handle.seek(offset)
                data = handle.read(requested)
            return {'path': str(file_path), 'size': size, 'offset': offset, 'bytes_returned': len(data), 'content_base64': base64.b64encode(data).decode('ascii')}
        return self._execute('read_binary_file', arguments, operation, source=source)
