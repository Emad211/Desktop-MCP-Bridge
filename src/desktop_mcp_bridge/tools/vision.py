from __future__ import annotations

import io
import time
from typing import Any

from ..security import require_capability


class VisionToolsMixin:
    def capture_desktop_artifact(
        self,
        monitor: int = 1,
        max_width: int = 1920,
        image_format: str = "png",
        ttl_seconds: int | None = None,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        arguments = {
            "monitor": monitor,
            "max_width": max_width,
            "image_format": image_format,
            "ttl_seconds": ttl_seconds,
        }

        def operation() -> dict[str, Any]:
            require_capability(self.settings, "enable_desktop_control")
            data, metadata = self.observe_desktop_bytes(
                monitor=monitor,
                max_width=max_width,
                image_format=image_format,
                source=source,
            )
            stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime())
            artifact = self.artifacts.create(
                data,
                filename=f"desktop-{monitor}-{stamp}.{metadata['extension']}",
                mime_type=metadata["mime_type"],
                ttl_seconds=ttl_seconds,
            )
            return {
                "artifact": artifact,
                "capture": metadata,
            }

        return self._execute(
            "capture_desktop_artifact", arguments, operation, source=source
        )

    def screen_ocr(
        self,
        monitor: int = 1,
        language: str = "eng",
        min_confidence: float = 35.0,
        include_image: bool = True,
        max_width: int = 2560,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        arguments = {
            "monitor": monitor,
            "language": language,
            "min_confidence": min_confidence,
            "include_image": include_image,
            "max_width": max_width,
        }

        def operation() -> dict[str, Any]:
            require_capability(self.settings, "enable_ocr")
            try:
                import pytesseract
                from PIL import Image as PILImage
            except ImportError as exc:
                raise RuntimeError(
                    "OCR dependencies are missing. Re-run scripts/install.ps1 without -SkipOCR."
                ) from exc

            if self.settings.tesseract_command:
                pytesseract.pytesseract.tesseract_cmd = self.settings.tesseract_command

            data, metadata = self.observe_desktop_bytes(
                monitor=monitor,
                max_width=max_width,
                image_format="png",
                source=source,
            )
            image = PILImage.open(io.BytesIO(data))
            try:
                config = ""
                if self.settings.tessdata_dir:
                    config = f'--tessdata-dir "{self.settings.tessdata_dir}"'
                ocr = pytesseract.image_to_data(
                    image,
                    lang=language,
                    config=config,
                    output_type=pytesseract.Output.DICT,
                )
            except pytesseract.TesseractNotFoundError as exc:
                raise RuntimeError(
                    "Tesseract was not found. Install it or set DMB_TESSERACT_COMMAND."
                ) from exc

            items: list[dict[str, Any]] = []
            lines: list[str] = []
            count = len(ocr.get("text", []))
            for index in range(count):
                text = str(ocr["text"][index]).strip()
                try:
                    confidence = float(ocr["conf"][index])
                except (TypeError, ValueError):
                    confidence = -1.0
                if not text or confidence < min_confidence:
                    continue
                item = {
                    "text": text,
                    "confidence": confidence,
                    "box": {
                        "x": int(ocr["left"][index]),
                        "y": int(ocr["top"][index]),
                        "width": int(ocr["width"][index]),
                        "height": int(ocr["height"][index]),
                    },
                    "page": int(ocr.get("page_num", [1] * count)[index]),
                    "block": int(ocr.get("block_num", [0] * count)[index]),
                    "paragraph": int(ocr.get("par_num", [0] * count)[index]),
                    "line": int(ocr.get("line_num", [0] * count)[index]),
                }
                items.append(item)
                lines.append(text)

            result: dict[str, Any] = {
                "text": " ".join(lines),
                "items": items,
                "count": len(items),
                "language": language,
                "capture": metadata,
            }
            if include_image:
                stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime())
                result["artifact"] = self.artifacts.create(
                    data,
                    filename=f"ocr-desktop-{monitor}-{stamp}.png",
                    mime_type="image/png",
                )
            return result

        return self._execute("screen_ocr", arguments, operation, source=source)
