from __future__ import annotations

import os
import queue
import threading
import time
from concurrent.futures import Future
from pathlib import Path
from typing import Any

from ..security import (
    require_capability,
    require_full_access,
    resolve_allowed_path,
    validate_browser_url,
)


class BrowserWorker:
    """Run Playwright on one thread and fall back to installed Chromium browsers."""

    def __init__(
        self,
        profile_path: Path,
        downloads_path: Path,
        default_headless: bool,
        *,
        preferred_channel: str = "auto",
        executable_path: Path | None = None,
    ) -> None:
        self.profile_path = profile_path
        self.downloads_path = downloads_path
        self.default_headless = default_headless
        self.preferred_channel = preferred_channel
        self.executable_path = executable_path
        self._queue: queue.Queue[
            tuple[str, dict[str, Any], Future[Any]] | None
        ] = queue.Queue()
        self._thread = threading.Thread(
            target=self._run,
            name="desktop-bridge-browser",
            daemon=True,
        )
        self._thread.start()

    def submit(self, operation: str, **kwargs: Any) -> Any:
        if not self._thread.is_alive():
            raise RuntimeError("Browser worker is not running")
        future: Future[Any] = Future()
        self._queue.put((operation, kwargs, future))
        return future.result(timeout=max(45, int(kwargs.get("timeout_seconds", 30)) + 15))

    def close(self) -> None:
        if not self._thread.is_alive():
            return
        self._queue.put(None)
        self._thread.join(timeout=10)

    def _run(self) -> None:
        playwright = None
        context = None
        current_page_index = 0
        active_backend: dict[str, Any] | None = None
        launch_errors: list[dict[str, str]] = []

        def ensure_context(headless: bool | None = None) -> Any:
            nonlocal playwright, context, current_page_index, active_backend
            nonlocal launch_errors
            if context is not None:
                return context
            try:
                from playwright.sync_api import sync_playwright
            except ImportError as exc:
                raise RuntimeError(
                    "Playwright is not installed. Re-run scripts/install.ps1."
                ) from exc

            self.profile_path.mkdir(parents=True, exist_ok=True)
            self.downloads_path.mkdir(parents=True, exist_ok=True)
            playwright = sync_playwright().start()
            launch_errors = []
            requested_headless = (
                self.default_headless if headless is None else bool(headless)
            )
            common = {
                "user_data_dir": str(self.profile_path),
                "headless": requested_headless,
                "accept_downloads": True,
                "downloads_path": str(self.downloads_path),
                "viewport": {"width": 1440, "height": 960},
                "args": ["--disable-blink-features=AutomationControlled"],
            }

            for candidate in _launch_candidates(
                self.preferred_channel,
                self.executable_path,
            ):
                try:
                    launch_kwargs = {**common, **candidate["kwargs"]}
                    context = playwright.chromium.launch_persistent_context(
                        **launch_kwargs
                    )
                    active_backend = {
                        "label": candidate["label"],
                        "channel": candidate.get("channel"),
                        "executable_path": candidate.get("executable_path"),
                        "headless": requested_headless,
                    }
                    break
                except Exception as exc:
                    launch_errors.append(
                        {
                            "candidate": candidate["label"],
                            "error": f"{type(exc).__name__}: {exc}",
                        }
                    )
                    context = None

            if context is None:
                if playwright is not None:
                    playwright.stop()
                    playwright = None
                details = "; ".join(
                    f"{item['candidate']}: {item['error']}"
                    for item in launch_errors
                )
                raise RuntimeError(
                    "No compatible Chromium browser could be launched. "
                    "Install Edge/Chrome or the Playwright Chromium runtime. "
                    f"Attempts: {details}"
                )

            if not context.pages:
                context.new_page()
            current_page_index = 0
            return context

        def page() -> Any:
            nonlocal current_page_index
            active_context = ensure_context()
            pages = active_context.pages
            if not pages:
                pages = [active_context.new_page()]
            current_page_index = max(
                0,
                min(current_page_index, len(pages) - 1),
            )
            return pages[current_page_index]

        while True:
            item = self._queue.get()
            if item is None:
                break
            operation, kwargs, future = item
            try:
                if operation == "start":
                    active_context = ensure_context(kwargs.get("headless"))
                    result = {
                        "started": True,
                        "pages": len(active_context.pages),
                        "backend": active_backend,
                        "launch_errors": launch_errors,
                    }
                elif operation == "status":
                    result = {
                        "started": context is not None,
                        "pages": 0 if context is None else len(context.pages),
                        "current_page_index": current_page_index,
                        "profile_path": str(self.profile_path),
                        "downloads_path": str(self.downloads_path),
                        "preferred_channel": self.preferred_channel,
                        "configured_executable": (
                            None
                            if self.executable_path is None
                            else str(self.executable_path)
                        ),
                        "backend": active_backend,
                        "launch_errors": launch_errors,
                    }
                    if context is not None and context.pages:
                        current = page()
                        result.update(
                            {"url": current.url, "title": current.title()}
                        )
                elif operation == "navigate":
                    current = page()
                    response = current.goto(
                        kwargs["url"],
                        wait_until=kwargs.get(
                            "wait_until", "domcontentloaded"
                        ),
                        timeout=int(
                            kwargs.get("timeout_seconds", 30) * 1000
                        ),
                    )
                    result = {
                        "url": current.url,
                        "title": current.title(),
                        "status": (
                            None if response is None else response.status
                        ),
                        "backend": active_backend,
                    }
                elif operation == "snapshot":
                    current = page()
                    max_chars = max(
                        1_000,
                        min(
                            int(kwargs.get("max_chars", 60_000)),
                            200_000,
                        ),
                    )
                    try:
                        aria = current.locator("body").aria_snapshot(
                            timeout=10_000
                        )
                    except Exception:
                        aria = ""
                    elements = current.evaluate(_VISIBLE_ELEMENTS_SCRIPT)
                    console_messages = []
                    page_errors = []
                    if hasattr(current, "console_messages"):
                        console_messages = [
                            str(value)
                            for value in current.console_messages()[-20:]
                        ]
                    if hasattr(current, "page_errors"):
                        page_errors = [
                            str(value)
                            for value in current.page_errors()[-20:]
                        ]
                    result = {
                        "url": current.url,
                        "title": current.title(),
                        "aria_snapshot": str(aria)[:max_chars],
                        "interactive_elements": elements[:500],
                        "console_messages": console_messages,
                        "page_errors": page_errors,
                        "backend": active_backend,
                    }
                elif operation == "interact":
                    current = page()
                    locator = _locator(current, kwargs["selector"])
                    action = kwargs["action"]
                    timeout_ms = int(
                        kwargs.get("timeout_seconds", 30) * 1000
                    )
                    value = kwargs.get("value")
                    if action == "click":
                        locator.click(timeout=timeout_ms)
                    elif action == "double_click":
                        locator.dblclick(timeout=timeout_ms)
                    elif action == "fill":
                        locator.fill(
                            "" if value is None else str(value),
                            timeout=timeout_ms,
                        )
                    elif action == "type":
                        locator.press_sequentially(
                            "" if value is None else str(value),
                            delay=20,
                            timeout=timeout_ms,
                        )
                    elif action == "press":
                        locator.press(str(value), timeout=timeout_ms)
                    elif action == "check":
                        locator.check(timeout=timeout_ms)
                    elif action == "uncheck":
                        locator.uncheck(timeout=timeout_ms)
                    elif action == "select":
                        locator.select_option(
                            str(value), timeout=timeout_ms
                        )
                    elif action == "hover":
                        locator.hover(timeout=timeout_ms)
                    elif action == "focus":
                        locator.focus(timeout=timeout_ms)
                    else:
                        raise ValueError(
                            f"Unsupported browser action: {action}"
                        )
                    result = {
                        "action": action,
                        "url": current.url,
                        "title": current.title(),
                    }
                elif operation == "tabs":
                    active_context = ensure_context()
                    tab_operation = kwargs["tab_operation"]
                    if tab_operation == "list":
                        result = {
                            "current_page_index": current_page_index,
                            "tabs": [
                                {
                                    "index": index,
                                    "url": tab.url,
                                    "title": tab.title(),
                                }
                                for index, tab in enumerate(
                                    active_context.pages
                                )
                            ],
                        }
                    elif tab_operation == "new":
                        new_page = active_context.new_page()
                        current_page_index = (
                            len(active_context.pages) - 1
                        )
                        if kwargs.get("url"):
                            new_page.goto(
                                str(kwargs["url"]),
                                wait_until="domcontentloaded",
                            )
                        result = {
                            "current_page_index": current_page_index,
                            "url": new_page.url,
                        }
                    elif tab_operation == "switch":
                        requested = int(kwargs["index"])
                        if requested < 0 or requested >= len(
                            active_context.pages
                        ):
                            raise IndexError(
                                "Browser tab index is out of range"
                            )
                        current_page_index = requested
                        current = page()
                        current.bring_to_front()
                        result = {
                            "current_page_index": current_page_index,
                            "url": current.url,
                        }
                    elif tab_operation == "close":
                        current = page()
                        current.close()
                        current_page_index = max(
                            0, current_page_index - 1
                        )
                        result = {
                            "closed": True,
                            "current_page_index": current_page_index,
                        }
                    else:
                        raise ValueError(
                            f"Unsupported tab operation: {tab_operation}"
                        )
                elif operation == "screenshot":
                    current = page()
                    image_format = str(
                        kwargs.get("image_format", "png")
                    ).lower()
                    if image_format == "jpg":
                        image_format = "jpeg"
                    if image_format not in {"png", "jpeg"}:
                        raise ValueError(
                            "image_format must be png, jpg, or jpeg"
                        )
                    data = current.screenshot(
                        full_page=bool(kwargs.get("full_page", True)),
                        type=image_format,
                        quality=(
                            kwargs.get("quality")
                            if image_format == "jpeg"
                            else None
                        ),
                        animations="disabled",
                        caret="hide",
                    )
                    result = {
                        "data": data,
                        "url": current.url,
                        "title": current.title(),
                        "format": image_format,
                    }
                elif operation == "upload":
                    current = page()
                    locator = _locator(current, kwargs["selector"])
                    locator.set_input_files(kwargs["path"])
                    result = {
                        "uploaded": kwargs["path"],
                        "url": current.url,
                    }
                elif operation == "download":
                    current = page()
                    locator = _locator(current, kwargs["selector"])
                    timeout_ms = int(
                        kwargs.get("timeout_seconds", 30) * 1000
                    )
                    with current.expect_download(
                        timeout=timeout_ms
                    ) as info:
                        locator.click()
                    download = info.value
                    destination = Path(kwargs["destination"])
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    download.save_as(str(destination))
                    result = {
                        "path": str(destination),
                        "suggested_filename": download.suggested_filename,
                        "url": download.url,
                    }
                elif operation == "evaluate":
                    current = page()
                    result = {
                        "value": current.evaluate(kwargs["expression"]),
                        "url": current.url,
                    }
                elif operation == "close":
                    if context is not None:
                        context.close()
                        context = None
                    if playwright is not None:
                        playwright.stop()
                        playwright = None
                    current_page_index = 0
                    active_backend = None
                    launch_errors = []
                    result = {"closed": True}
                else:
                    raise ValueError(
                        f"Unknown browser operation: {operation}"
                    )
                future.set_result(result)
            except Exception as exc:
                future.set_exception(exc)

        if context is not None:
            context.close()
        if playwright is not None:
            playwright.stop()


class BrowserToolsMixin:
    def _browser_execute(
        self,
        action: str,
        arguments: dict[str, Any],
        callback: Any,
        *,
        source: str,
    ) -> dict[str, Any]:
        def operation() -> dict[str, Any]:
            require_capability(self.settings, "enable_browser")
            return callback()

        return self._execute(
            action,
            arguments,
            operation,
            source=source,
        )

    def browser_status(self, *, source: str = "local") -> dict[str, Any]:
        return self._browser_execute(
            "browser_status",
            {},
            lambda: self.browser.submit("status"),
            source=source,
        )

    def browser_start(
        self,
        headless: bool | None = None,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        return self._browser_execute(
            "browser_start",
            {"headless": headless},
            lambda: self.browser.submit("start", headless=headless),
            source=source,
        )

    def browser_navigate(
        self,
        url: str,
        wait_until: str = "domcontentloaded",
        timeout_seconds: int = 30,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        return self._browser_execute(
            "browser_navigate",
            {
                "url": url,
                "wait_until": wait_until,
                "timeout_seconds": timeout_seconds,
            },
            lambda: self.browser.submit(
                "navigate",
                url=validate_browser_url(url, self.settings),
                wait_until=wait_until,
                timeout_seconds=timeout_seconds,
            ),
            source=source,
        )

    def browser_snapshot(
        self,
        max_chars: int = 60_000,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        return self._browser_execute(
            "browser_snapshot",
            {"max_chars": max_chars},
            lambda: self.browser.submit(
                "snapshot", max_chars=max_chars
            ),
            source=source,
        )

    def browser_interact(
        self,
        action: str,
        selector: dict[str, Any],
        value: Any = None,
        timeout_seconds: int = 30,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        return self._browser_execute(
            "browser_interact",
            {
                "action": action,
                "selector": selector,
                "value": value,
                "timeout_seconds": timeout_seconds,
            },
            lambda: self.browser.submit(
                "interact",
                action=action,
                selector=selector,
                value=value,
                timeout_seconds=timeout_seconds,
            ),
            source=source,
        )

    def browser_tabs(
        self,
        tab_operation: str,
        index: int | None = None,
        url: str | None = None,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        def callback() -> dict[str, Any]:
            target = url
            if target is not None:
                target = validate_browser_url(target, self.settings)
            return self.browser.submit(
                "tabs",
                tab_operation=tab_operation,
                index=index,
                url=target,
            )

        return self._browser_execute(
            "browser_tabs",
            {
                "tab_operation": tab_operation,
                "index": index,
                "url": url,
            },
            callback,
            source=source,
        )

    def browser_screenshot(
        self,
        full_page: bool = True,
        image_format: str = "png",
        quality: int = 85,
        ttl_seconds: int | None = None,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        arguments = {
            "full_page": full_page,
            "image_format": image_format,
            "quality": quality,
            "ttl_seconds": ttl_seconds,
        }

        def callback() -> dict[str, Any]:
            result = self.browser.submit(
                "screenshot",
                full_page=full_page,
                image_format=image_format,
                quality=quality,
            )
            extension = (
                "jpg" if image_format in {"jpg", "jpeg"} else "png"
            )
            mime_format = "jpeg" if extension == "jpg" else "png"
            artifact = self.artifacts.create(
                result.pop("data"),
                filename=(
                    f"browser-{int(time.time())}.{extension}"
                ),
                mime_type=f"image/{mime_format}",
                ttl_seconds=ttl_seconds,
            )
            return {**result, "artifact": artifact}

        return self._browser_execute(
            "browser_screenshot",
            arguments,
            callback,
            source=source,
        )

    def browser_upload(
        self,
        selector: dict[str, Any],
        path: str,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        def callback() -> dict[str, Any]:
            resolved = resolve_allowed_path(
                path,
                self.settings,
                must_exist=True,
            )
            return self.browser.submit(
                "upload",
                selector=selector,
                path=str(resolved),
            )

        return self._browser_execute(
            "browser_upload",
            {"selector": selector, "path": path},
            callback,
            source=source,
        )

    def browser_download(
        self,
        selector: dict[str, Any],
        destination: str,
        timeout_seconds: int = 30,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        def callback() -> dict[str, Any]:
            resolved = resolve_allowed_path(
                destination,
                self.settings,
                must_exist=False,
            )
            return self.browser.submit(
                "download",
                selector=selector,
                destination=str(resolved),
                timeout_seconds=timeout_seconds,
            )

        return self._browser_execute(
            "browser_download",
            {
                "selector": selector,
                "destination": destination,
                "timeout_seconds": timeout_seconds,
            },
            callback,
            source=source,
        )

    def browser_evaluate(
        self,
        expression: str,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        require_full_access(self.settings, "browser_evaluate")
        return self._browser_execute(
            "browser_evaluate",
            {"expression": expression},
            lambda: self.browser.submit(
                "evaluate", expression=expression
            ),
            source=source,
        )

    def browser_close(
        self,
        *,
        source: str = "local",
    ) -> dict[str, Any]:
        return self._browser_execute(
            "browser_close",
            {},
            lambda: self.browser.submit("close"),
            source=source,
        )


def _launch_candidates(
    preferred_channel: str,
    explicit_path: Path | None,
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    seen: set[str] = set()

    def add(
        label: str,
        *,
        channel: str | None = None,
        executable_path: Path | None = None,
    ) -> None:
        key = f"{channel or ''}|{executable_path or ''}"
        if key in seen:
            return
        seen.add(key)
        kwargs: dict[str, Any] = {}
        if channel:
            kwargs["channel"] = channel
        if executable_path:
            kwargs["executable_path"] = str(executable_path)
        candidates.append(
            {
                "label": label,
                "channel": channel,
                "executable_path": (
                    None
                    if executable_path is None
                    else str(executable_path)
                ),
                "kwargs": kwargs,
            }
        )

    if explicit_path is not None:
        add("configured-executable", executable_path=explicit_path)

    order = {
        "auto": ["chromium", "msedge", "chrome"],
        "chromium": ["chromium", "msedge", "chrome"],
        "msedge": ["msedge", "chromium", "chrome"],
        "chrome": ["chrome", "chromium", "msedge"],
    }.get(preferred_channel, ["chromium", "msedge", "chrome"])

    for item in order:
        if item == "chromium":
            add("playwright-chromium")
        else:
            add(f"channel-{item}", channel=item)

    for label, path in _system_browser_paths():
        add(label, executable_path=path)

    return candidates


def _system_browser_paths() -> list[tuple[str, Path]]:
    if os.name != "nt":
        return []
    roots = [
        os.environ.get("PROGRAMFILES"),
        os.environ.get("PROGRAMFILES(X86)"),
        os.environ.get("LOCALAPPDATA"),
    ]
    relative_paths = [
        (
            "system-edge",
            Path("Microsoft") / "Edge" / "Application" / "msedge.exe",
        ),
        (
            "system-chrome",
            Path("Google") / "Chrome" / "Application" / "chrome.exe",
        ),
        (
            "user-chrome",
            Path("Google") / "Chrome" / "Application" / "chrome.exe",
        ),
    ]
    rows: list[tuple[str, Path]] = []
    seen: set[Path] = set()
    for root in roots:
        if not root:
            continue
        for label, relative in relative_paths:
            candidate = (Path(root) / relative).resolve()
            if candidate in seen or not candidate.exists():
                continue
            seen.add(candidate)
            rows.append((label, candidate))
    return rows


def _locator(page: Any, selector: dict[str, Any]) -> Any:
    kind = str(selector.get("kind", "css"))
    value = selector.get("value")
    if value is None and kind != "role":
        raise ValueError("selector.value is required")
    exact = bool(selector.get("exact", False))
    if kind == "css":
        locator = page.locator(str(value))
    elif kind == "text":
        locator = page.get_by_text(str(value), exact=exact)
    elif kind == "label":
        locator = page.get_by_label(str(value), exact=exact)
    elif kind == "placeholder":
        locator = page.get_by_placeholder(str(value), exact=exact)
    elif kind == "testid":
        locator = page.get_by_test_id(str(value))
    elif kind == "role":
        role = str(selector.get("role") or value)
        name = selector.get("name")
        locator = page.get_by_role(role, name=name, exact=exact)
    else:
        raise ValueError(f"Unsupported selector kind: {kind}")
    nth = selector.get("nth")
    return locator.nth(int(nth)) if nth is not None else locator


_VISIBLE_ELEMENTS_SCRIPT = r"""
() => {
  const visible = (el) => {
    const style = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return style.visibility !== 'hidden' && style.display !== 'none' && r.width > 0 && r.height > 0;
  };
  const text = (el) => (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim().replace(/\s+/g, ' ').slice(0, 300);
  return Array.from(document.querySelectorAll('a,button,input,textarea,select,[role],[contenteditable="true"]'))
    .filter(visible)
    .slice(0, 500)
    .map((el, index) => {
      const r = el.getBoundingClientRect();
      return {
        index,
        tag: el.tagName.toLowerCase(),
        role: el.getAttribute('role'),
        name: el.getAttribute('aria-label') || el.getAttribute('name') || null,
        text: text(el),
        id: el.id || null,
        type: el.getAttribute('type'),
        placeholder: el.getAttribute('placeholder'),
        disabled: Boolean(el.disabled),
        box: {x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height)}
      };
    });
}
"""
