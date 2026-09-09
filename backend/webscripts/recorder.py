"""Recording loop.

The browser stays under the user's control; we only poll the page for the
events the injected recorder buffered, and turn them into steps.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Callable

from selenium.common.exceptions import WebDriverException
from selenium.webdriver.common.by import By

from . import config
from .models import Step, Target

_JS_DIR = Path(__file__).parent / "js"
RECORDER_JS = (_JS_DIR / "recorder.js").read_text("utf-8")

DRAIN_JS = (
    "return (window.__WS_RECORDER__ && window.__WS_RECORDER__.alive) "
    "? window.__WS_RECORDER__.drain() : null;"
)

MAX_FRAME_DEPTH = 3
MAX_FRAMES_PER_LEVEL = 12
# A URL change more than this many seconds after the last interaction is
# treated as the user navigating by hand (address bar, bookmark).
MANUAL_NAV_GAP = 4.0


class Recorder:
    def __init__(
        self,
        driver,
        on_step: Callable[[Step], None] | None = None,
        on_log: Callable[[str, str], None] | None = None,
        capture_scroll: bool = False,
        poll: float | None = None,
    ) -> None:
        self.driver = driver
        self.on_step = on_step or (lambda step: None)
        self.on_log = on_log or (lambda level, msg: None)
        self.capture_scroll = capture_scroll
        self.poll = poll if poll is not None else config.RECORDER_POLL
        self.steps: list[Step] = []
        self._last_ts: int = 0
        self._last_url: str = ""
        self._handles: list[str] = []

    # ---------------------------------------------------------------- public

    def start(self, url: str) -> None:
        """Open the starting page and record it as the first step."""
        if url:
            self.driver.get(url)
            self._append(
                Step(action="goto", url=self.driver.current_url, label=url, ts=_now_ms())
            )
        self._last_url = _safe(lambda: self.driver.current_url, "")
        self._handles = _safe(lambda: list(self.driver.window_handles), [])

    def loop(self, should_stop: Callable[[], bool]) -> list[Step]:
        """Poll until `should_stop()` or the browser is gone."""
        while not should_stop():
            try:
                self._tick()
            except WebDriverException as exc:
                if _browser_closed(exc):
                    self.on_log("info", "براوزر وتړل شو — ثبتول ودرېدل.")
                    break
                self.on_log("warn", f"د ثبتولو خبرداری: {_short(exc)}")
            except Exception as exc:  # noqa: BLE001
                self.on_log("warn", f"د ثبتولو خبرداری: {exc}")
            time.sleep(self.poll)
        # Final drain so the last click is not lost.
        try:
            self._tick()
        except Exception:  # noqa: BLE001
            pass
        return self.steps

    # --------------------------------------------------------------- internal

    def _tick(self) -> None:
        self._sync_windows()
        events = self._drain_all()
        events.sort(key=lambda e: e.get("ts", 0))
        for event in events:
            step = self._to_step(event)
            if step is not None:
                self._append(step)
        self._check_navigation()

    def _sync_windows(self) -> None:
        handles = list(self.driver.window_handles)
        if handles == self._handles:
            return
        opened = [h for h in handles if h not in self._handles]
        if opened:
            self.driver.switch_to.window(opened[-1])
            self._append(Step(action="switch_window", value="new", ts=_now_ms()))
            self.on_log("info", "نوې کړکۍ/ټب پرانیستل شو.")
        elif self.driver.current_window_handle not in handles and handles:
            self.driver.switch_to.window(handles[-1])
        self._handles = handles
        self._last_url = _safe(lambda: self.driver.current_url, self._last_url)

    def _drain_all(self) -> list[dict]:
        out: list[dict] = []
        self.driver.switch_to.default_content()
        self._walk([], out, 0)
        self.driver.switch_to.default_content()
        return out

    def _walk(self, path: list[int], out: list[dict], depth: int) -> None:
        for event in self._drain_current():
            event["frame_path"] = list(path)
            out.append(event)
        if depth >= MAX_FRAME_DEPTH:
            return
        try:
            frames = self.driver.find_elements(By.CSS_SELECTOR, "iframe, frame")
        except WebDriverException:
            return
        for index in range(min(len(frames), MAX_FRAMES_PER_LEVEL)):
            try:
                self.driver.switch_to.frame(index)
            except WebDriverException:
                continue
            try:
                self._walk(path + [index], out, depth + 1)
            finally:
                try:
                    self.driver.switch_to.parent_frame()
                except WebDriverException:
                    self.driver.switch_to.default_content()
                    self._reenter(path)

    def _reenter(self, path: list[int]) -> None:
        for index in path:
            try:
                self.driver.switch_to.frame(index)
            except WebDriverException:
                return

    def _drain_current(self) -> list[dict]:
        result = self.driver.execute_script(DRAIN_JS)
        if result is None:
            # First visit to this document, or it navigated: (re)inject.
            self.driver.execute_script(RECORDER_JS)
            self.driver.execute_script(
                "if (window.__WS_RECORDER__) "
                "window.__WS_RECORDER__.opts.captureScroll = arguments[0];",
                bool(self.capture_scroll),
            )
            return []
        return [e for e in result if isinstance(e, dict)]

    def _check_navigation(self) -> None:
        url = _safe(lambda: self.driver.current_url, self._last_url)
        if url == self._last_url:
            return
        gap = (_now_ms() - self._last_ts) / 1000.0 if self._last_ts else 999.0
        self._last_url = url
        if gap > MANUAL_NAV_GAP and not url.startswith("about:"):
            # No recent click caused this, so the user navigated manually.
            self._append(Step(action="goto", url=url, label=url, ts=_now_ms()))

    def _to_step(self, event: dict) -> Step | None:
        action = event.get("action")
        if action not in {"click", "type", "select", "press_key", "scroll", "hover"}:
            return None
        targets = [
            Target(**t)
            for t in event.get("targets", [])
            if isinstance(t, dict) and t.get("value")
        ]
        if action != "scroll" and not targets:
            return None

        secret = bool(event.get("secret"))
        value = event.get("value")
        if action == "type" and secret:
            value = None  # filled from a variable at run time

        return Step(
            action=action,
            targets=targets,
            value=value,
            option_value=event.get("optionValue"),
            url=event.get("url"),
            frame_path=[int(i) for i in event.get("frame_path", [])],
            label=str(event.get("label") or "")[:120],
            tag=event.get("tag"),
            secret=secret,
            ts=int(event.get("ts") or _now_ms()),
        )

    def _append(self, step: Step) -> None:
        if self._last_ts and step.ts:
            step.delay_ms = max(0, min(step.ts - self._last_ts, 8000))
        if step.ts:
            self._last_ts = step.ts
        if self._is_noise(step):
            return
        self.steps.append(step)
        self.on_step(step)

    def _is_noise(self, step: Step) -> bool:
        """Drop steps that add nothing to the replay."""
        if not self.steps:
            return False
        previous = self.steps[-1]
        if step.action == "goto" and previous.action == "goto":
            # Redirect chain: keep only the final URL.
            self.steps[-1] = step
            return True
        if (
            step.action == "click"
            and previous.action == "click"
            and step.delay_ms < 250
            and _same_target(step, previous)
        ):
            return True
        return False


def _same_target(a: Step, b: Step) -> bool:
    if not a.targets or not b.targets:
        return False
    return a.targets[0].value == b.targets[0].value


def _now_ms() -> int:
    return int(time.time() * 1000)


def _safe(fn, fallback):
    try:
        return fn()
    except Exception:  # noqa: BLE001
        return fallback


def _browser_closed(exc: Exception) -> bool:
    text = str(exc).lower()
    return any(
        marker in text
        for marker in (
            "no such window",
            "target window already closed",
            "web view not found",
            "invalid session id",
            "disconnected",
            "chrome not reachable",
            "unable to connect",
        )
    )


def _short(exc: Exception) -> str:
    return str(exc).split("\n", 1)[0][:200]
