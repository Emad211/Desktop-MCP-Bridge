from __future__ import annotations

from typing import Any

from ..security import require_capability


class ClipboardToolsMixin:

    def clipboard_read(self, *, source: str='local') -> dict[str, Any]:

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_clipboard')
            import pyperclip
            text = pyperclip.paste()
            return {'text': text, 'characters': len(text)}
        return self._execute('clipboard_read', {}, operation, source=source)

    def clipboard_write(self, text: str, *, source: str='local') -> dict[str, Any]:

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_clipboard')
            import pyperclip
            pyperclip.copy(text)
            return {'characters': len(text)}
        return self._execute('clipboard_write', {'text_length': len(text)}, operation, source=source)
