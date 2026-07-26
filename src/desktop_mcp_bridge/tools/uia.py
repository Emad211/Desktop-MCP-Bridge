from __future__ import annotations

import os
from typing import Any

from ..security import require_capability


class UIAutomationToolsMixin:

    def uia_tree(self, title_re: str='.*', depth: int=4, max_elements: int=500, *, source: str='local') -> dict[str, Any]:
        arguments = {'title_re': title_re, 'depth': depth, 'max_elements': max_elements}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_ui_automation')
            if os.name != 'nt':
                raise OSError('UI Automation is only supported on Windows')
            try:
                from pywinauto import Desktop
            except ImportError as exc:
                raise RuntimeError('Install pywinauto to enable UI Automation') from exc
            desktop = Desktop(backend='uia')
            window = desktop.window(title_re=title_re)
            root = window.wrapper_object()
            elements: list[dict[str, Any]] = []

            def walk(node: Any, level: int) -> None:
                if level > depth or len(elements) >= max_elements:
                    return
                info = node.element_info
                rect = info.rectangle
                elements.append({'index': len(elements), 'level': level, 'name': info.name, 'control_type': info.control_type, 'automation_id': info.automation_id, 'class_name': info.class_name, 'enabled': info.enabled, 'visible': info.visible, 'rectangle': [rect.left, rect.top, rect.right, rect.bottom]})
                for child in node.children():
                    walk(child, level + 1)
            walk(root, 0)
            return {'window': root.window_text(), 'elements': elements, 'count': len(elements)}
        return self._execute('uia_tree', arguments, operation, source=source)

    def uia_invoke(self, title_re: str, selector: dict[str, Any], action: str='click', value: str | None=None, *, source: str='local') -> dict[str, Any]:
        arguments = {'title_re': title_re, 'selector': selector, 'action': action, 'value_length': len(value) if value is not None else None}

        def operation() -> dict[str, Any]:
            require_capability(self.settings, 'enable_ui_automation')
            if os.name != 'nt':
                raise OSError('UI Automation is only supported on Windows')
            try:
                from pywinauto import Desktop
            except ImportError as exc:
                raise RuntimeError('Install pywinauto to enable UI Automation') from exc
            window = Desktop(backend='uia').window(title_re=title_re)
            element = window.child_window(**selector).wrapper_object()
            normalized = action.lower()
            if normalized == 'click':
                element.click_input()
            elif normalized == 'invoke':
                element.invoke()
            elif normalized == 'focus':
                element.set_focus()
            elif normalized == 'set_text':
                if value is None:
                    raise ValueError('set_text requires value')
                element.set_edit_text(value)
            elif normalized == 'type_text':
                if value is None:
                    raise ValueError('type_text requires value')
                element.type_keys(value, with_spaces=True, set_foreground=True)
            elif normalized == 'select':
                element.select()
            else:
                raise ValueError('Unsupported UIA action')
            return {'action': normalized, 'name': element.element_info.name, 'control_type': element.element_info.control_type}
        return self._execute('uia_invoke', arguments, operation, source=source)
