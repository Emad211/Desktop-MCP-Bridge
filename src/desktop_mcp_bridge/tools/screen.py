from __future__ import annotations

import base64
import io
from typing import Any

from ..security import require_capability


class ScreenToolsMixin:

    def observe_desktop_bytes(self, monitor: int=1, max_width: int=1920, quality: int=85, image_format: str='png', *, source: str='local') -> tuple[bytes, dict[str, Any]]:
        arguments = {'monitor': monitor, 'max_width': max_width, 'quality': quality, 'image_format': image_format}

        def operation() -> tuple[bytes, dict[str, Any]]:
            import mss
            import pyautogui
            from PIL import Image as PILImage
            pyautogui.FAILSAFE = True
            pyautogui.PAUSE = 0.03
            require_capability(self.settings, 'enable_desktop_control')
            with mss.mss() as capture:
                if monitor < 0 or monitor >= len(capture.monitors):
                    raise ValueError(f'Invalid monitor index. Available: 0..{len(capture.monitors) - 1}')
                geometry = capture.monitors[monitor]
                shot = capture.grab(geometry)
                image = PILImage.frombytes('RGB', shot.size, shot.rgb)
                original = image.size
                if max_width > 0 and image.width > max_width:
                    ratio = max_width / image.width
                    image = image.resize((max_width, max(1, int(image.height * ratio))))
                buffer = io.BytesIO()
                normalized = image_format.lower()
                if normalized in {'jpg', 'jpeg'}:
                    image.save(buffer, format='JPEG', quality=max(20, min(quality, 95)), optimize=True)
                    mime_type = 'image/jpeg'
                    extension = 'jpg'
                else:
                    image.save(buffer, format='PNG', optimize=True)
                    mime_type = 'image/png'
                    extension = 'png'
                metadata = {'monitor': monitor, 'geometry': dict(geometry), 'original_size': original, 'returned_size': image.size, 'mime_type': mime_type, 'extension': extension, 'cursor': tuple(pyautogui.position())}
                return (buffer.getvalue(), metadata)
        return self._execute('observe_desktop', arguments, operation, source=source)

    def observe_desktop_base64(self, **kwargs: Any) -> dict[str, Any]:
        data, metadata = self.observe_desktop_bytes(**kwargs)
        return {**metadata, 'image_base64': base64.b64encode(data).decode('ascii')}
