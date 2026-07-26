from __future__ import annotations
import base64
import time
from typing import Any
from ..config import DesktopAction
from ..security import require_capability

class InputToolsMixin:

    def desktop_step(self, actions: list[dict[str, Any]], return_screenshot: bool=False, *, source: str='local') -> dict[str, Any]:
        arguments = {'actions': actions, 'return_screenshot': return_screenshot}

        def operation() -> dict[str, Any]:
            pyautogui = _pyautogui()
            require_capability(self.settings, 'enable_desktop_control')
            if not 1 <= len(actions) <= self.settings.max_desktop_actions:
                raise ValueError(f'actions must contain 1..{self.settings.max_desktop_actions} items')
            parsed = [DesktopAction.model_validate(action) for action in actions]
            for action in parsed:
                self._perform_action(action)
            result: dict[str, Any] = {'actions_executed': len(parsed), 'cursor': tuple(pyautogui.position())}
            if return_screenshot:
                data, metadata = self.observe_desktop_bytes(source=source)
                result['screenshot'] = {**metadata, 'image_base64': base64.b64encode(data).decode('ascii')}
            return result
        return self._execute('desktop_step', arguments, operation, source=source)

    @staticmethod
    def _perform_action(action: DesktopAction) -> None:
        pyautogui = _pyautogui()
        if action.type in {'click', 'double_click', 'move', 'drag'} and (action.x is None or action.y is None):
            raise ValueError(f'{action.type} requires x and y')
        if action.type == 'click':
            pyautogui.click(action.x, action.y, duration=action.duration, button=action.button)
        elif action.type == 'double_click':
            pyautogui.doubleClick(action.x, action.y, interval=0.12, duration=action.duration, button=action.button)
        elif action.type == 'move':
            pyautogui.moveTo(action.x, action.y, duration=action.duration)
        elif action.type == 'drag':
            pyautogui.dragTo(action.x, action.y, duration=action.duration, button=action.button)
        elif action.type == 'scroll':
            if action.amount is None:
                raise ValueError('scroll requires amount')
            pyautogui.scroll(action.amount)
        elif action.type == 'type':
            if action.text is None:
                raise ValueError('type requires text')
            pyautogui.write(action.text, interval=0.01)
        elif action.type == 'hotkey':
            if not action.keys:
                raise ValueError('hotkey requires keys')
            pyautogui.hotkey(*action.keys)
        elif action.type == 'press':
            if not action.key:
                raise ValueError('press requires key')
            pyautogui.press(action.key, presses=action.presses, interval=0.03)
        elif action.type == 'wait':
            time.sleep(action.seconds or 0)


def _pyautogui():
    import pyautogui
    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.03
    return pyautogui
