"""Replay engine: runs a recorded script step by step."""

from __future__ import annotations

import re
import time
from typing import Callable

from selenium.common.exceptions import (
    ElementClickInterceptedException,
    ElementNotInteractableException,
    StaleElementReferenceException,
    WebDriverException,
)
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import Select

from . import config
from .models import Script, Step

KEY_MAP = {
    "ENTER": Keys.ENTER,
    "ESCAPE": Keys.ESCAPE,
    "TAB": Keys.TAB,
    "SPACE": Keys.SPACE,
    "BACKSPACE": Keys.BACKSPACE,
    "DELETE": Keys.DELETE,
    "ARROW_UP": Keys.ARROW_UP,
    "ARROW_DOWN": Keys.ARROW_DOWN,
    "ARROW_LEFT": Keys.ARROW_LEFT,
    "ARROW_RIGHT": Keys.ARROW_RIGHT,
    "HOME": Keys.HOME,
    "END": Keys.END,
    "PAGE_UP": Keys.PAGE_UP,
    "PAGE_DOWN": Keys.PAGE_DOWN,
}

_VAR = re.compile(r"\{\{\s*([A-Za-z0-9_.\-]+)\s*\}\}")

SCROLL_INTO_VIEW = (
    "arguments[0].scrollIntoView({block:'center', inline:'center'});"
)


class StepFailed(RuntimeError):
    def __init__(self, step: Step, index: int, reason: str) -> None:
        super().__init__(reason)
        self.step = step
        self.index = index
        self.reason = reason


class Player:
    def __init__(
        self,
        driver,
        on_event: Callable[[dict], None] | None = None,
        should_stop: Callable[[], bool] | None = None,
        speed: float = 1.0,
        step_timeout: float | None = None,
    ) -> None:
        self.driver = driver
        self.on_event = on_event or (lambda payload: None)
        self.should_stop = should_stop or (lambda: False)
        self.speed = max(0.1, min(speed, 10.0))
        self.step_timeout = step_timeout or config.STEP_TIMEOUT

    # ---------------------------------------------------------------- public

    def play(self, script: Script, variables: dict[str, str] | None = None) -> dict:
        try:
            return self._play(script, variables or {})
        finally:
            # A run that ends inside an iframe would leave the session pointing
            # at that frame; the next run must start from the top document.
            try:
                self.driver.switch_to.default_content()
            except WebDriverException:
                pass

    def _play(self, script: Script, variables: dict[str, str]) -> dict:
        steps = [s for s in script.steps if s.enabled]
        started = time.time()
        done = 0

        for index, step in enumerate(steps):
            if self.should_stop():
                return self._result(script, steps, done, started, "stopped")
            self._sleep_before(step)
            self._emit(
                "step_start",
                index=index,
                total=len(steps),
                step_id=step.id,
                message=step.describe(),
            )
            try:
                self._execute(step, variables)
            except StepFailed as exc:
                self._emit(
                    "step_error",
                    index=index,
                    step_id=step.id,
                    message=f"ګام {index + 1} ناکام شو: {exc.reason}",
                )
                shot = self._screenshot(f"error_{script.id}_{index + 1}")
                return self._result(
                    script, steps, done, started, "failed",
                    error=exc.reason, failed_index=index, screenshot=shot,
                )
            done += 1
            self._emit(
                "step_done", index=index, step_id=step.id, message=step.describe()
            )
        return self._result(script, steps, done, started, "ok")

    # --------------------------------------------------------------- internal

    def _execute(self, step: Step, variables: dict[str, str]) -> None:
        action = step.action

        if action == "goto":
            url = self._expand(step.url or "", variables)
            self.driver.get(url)
            self._wait_ready()
            return

        if action == "wait":
            time.sleep(max(0.0, float(step.value or 0) / 1000.0))
            return

        if action == "switch_window":
            self._switch_window(step)
            return

        if action == "screenshot":
            self._screenshot(step.value or "shot")
            return

        if action == "scroll" and not step.targets:
            self._run_js("window.scrollTo(0, arguments[0]);", int(float(step.value or 0)))
            return

        if action == "assert_text":
            needle = self._expand(step.value or "", variables)
            body = self._run_js("return document.body ? document.body.innerText : '';")
            if needle and needle not in (body or ""):
                raise StepFailed(step, 0, f"متن ونه موندل شو: «{needle}»")
            return

        element = self._resolve(step)

        if action == "click":
            self._click(element, step)
        elif action == "type":
            self._type(element, step, variables)
        elif action == "select":
            self._select(element, step, variables)
        elif action == "press_key":
            self._press(element, step)
        elif action == "hover":
            self._hover(element)
        elif action == "scroll":
            self._run_js(SCROLL_INTO_VIEW, element)
        else:
            raise StepFailed(step, 0, f"ناپېژندلې کړنه: {action}")

    # -- element resolution ---------------------------------------------------

    def _resolve(self, step: Step):
        deadline = time.time() + self.step_timeout
        tried: list[str] = []
        while True:
            self._enter_frame(step.frame_path)
            for target in step.targets:
                by = By.CSS_SELECTOR if target.type == "css" else By.XPATH
                try:
                    candidates = self.driver.find_elements(by, target.value)
                except WebDriverException:
                    tried.append(target.value)
                    continue
                for element in candidates:
                    try:
                        if element.is_displayed():
                            return element
                    except StaleElementReferenceException:
                        continue
                    except WebDriverException:
                        continue
                # Nothing visible: an existing but hidden element still beats
                # nothing when it is the only match (e.g. custom widgets).
                if len(candidates) == 1:
                    return candidates[0]
                tried.append(target.value)
            if time.time() >= deadline:
                break
            time.sleep(0.35)

        label = step.label or (step.targets[0].value if step.targets else "?")
        raise StepFailed(
            step, 0,
            f"عنصر ونه موندل شو: «{label}» "
            f"({len(step.targets)} لارې وازمویل شوې، {self.step_timeout:.0f}s انتظار)",
        )

    def _enter_frame(self, frame_path: list[int]) -> None:
        self.driver.switch_to.default_content()
        for index in frame_path:
            try:
                self.driver.switch_to.frame(index)
            except WebDriverException:
                return

    # -- actions --------------------------------------------------------------

    def _click(self, element, step: Step) -> None:
        self._run_js(SCROLL_INTO_VIEW, element)
        time.sleep(0.12)
        try:
            element.click()
            return
        except (
            ElementClickInterceptedException,
            ElementNotInteractableException,
            StaleElementReferenceException,
        ):
            pass
        except WebDriverException:
            pass
        # Overlays, sticky headers and animated menus: click through JS.
        try:
            self._run_js("arguments[0].click();", element)
        except WebDriverException as exc:
            raise StepFailed(step, 0, f"کلیک ونه شو: {_short(exc)}") from exc

    def _type(self, element, step: Step, variables: dict[str, str]) -> None:
        text = step.value or ""
        if step.secret:
            name = _secret_var(step)
            if name not in variables:
                raise StepFailed(step, 0, f"د «{name}» ارزښت نه دی ورکړل شوی")
            text = variables[name]
        else:
            text = self._expand(text, variables)

        self._run_js(SCROLL_INTO_VIEW, element)
        try:
            element.click()
        except WebDriverException:
            self._run_js("arguments[0].focus();", element)
        # clear() does not fire the events React/Vue listen to, so select-all
        # + typing is the reliable way to replace existing content.
        try:
            element.send_keys(Keys.CONTROL, "a")
            element.send_keys(Keys.DELETE)
        except WebDriverException:
            pass
        try:
            element.send_keys(text)
        except WebDriverException as exc:
            raise StepFailed(step, 0, f"لیکل ونه شول: {_short(exc)}") from exc

    def _select(self, element, step: Step, variables: dict[str, str]) -> None:
        wanted = self._expand(step.value or "", variables)
        try:
            select = Select(element)
        except WebDriverException as exc:
            raise StepFailed(step, 0, f"د لیست عنصر نه دی: {_short(exc)}") from exc
        for attempt in (
            lambda: select.select_by_visible_text(wanted),
            lambda: select.select_by_value(step.option_value or wanted),
        ):
            try:
                attempt()
                return
            except WebDriverException:
                continue
        raise StepFailed(step, 0, f"انتخاب ونه موندل شو: «{wanted}»")

    def _press(self, element, step: Step) -> None:
        key = KEY_MAP.get((step.value or "").upper())
        if key is None:
            raise StepFailed(step, 0, f"ناپېژندلې تڼۍ: {step.value}")
        try:
            element.send_keys(key)
        except WebDriverException:
            self.driver.switch_to.active_element.send_keys(key)

    def _hover(self, element) -> None:
        from selenium.webdriver.common.action_chains import ActionChains

        self._run_js(SCROLL_INTO_VIEW, element)
        ActionChains(self.driver).move_to_element(element).perform()

    def _switch_window(self, step: Step) -> None:
        handles = self.driver.window_handles
        if not handles:
            return
        if step.value == "new":
            self.driver.switch_to.window(handles[-1])
        else:
            self.driver.switch_to.window(handles[0])
        self._wait_ready()

    # -- helpers --------------------------------------------------------------

    def _sleep_before(self, step: Step) -> None:
        # Replay a little faster than the human, but keep the rhythm so pages
        # have time to react.
        delay = min(step.delay_ms, 3000) / 1000.0 / self.speed
        time.sleep(max(0.15, min(delay, 3.0)))

    def _wait_ready(self, timeout: float = 20.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if self._run_js("return document.readyState;") == "complete":
                    return
            except WebDriverException:
                return
            time.sleep(0.2)

    def _run_js(self, script: str, *args):
        return self.driver.execute_script(script, *args)

    def _expand(self, text: str, variables: dict[str, str]) -> str:
        return _VAR.sub(lambda m: str(variables.get(m.group(1), m.group(0))), text)

    def _screenshot(self, name: str) -> str | None:
        try:
            config.SHOTS_DIR.mkdir(parents=True, exist_ok=True)
            safe = re.sub(r"[^A-Za-z0-9_.-]", "_", name)[:60]
            path = config.SHOTS_DIR / f"{safe}_{int(time.time())}.png"
            self.driver.save_screenshot(str(path))
            return str(path)
        except Exception:  # noqa: BLE001
            return None

    def _emit(self, kind: str, **payload) -> None:
        self.on_event({"type": kind, **payload})

    def _result(
        self, script: Script, steps: list[Step], done: int, started: float,
        status: str, **extra,
    ) -> dict:
        return {
            "script_id": script.id,
            "status": status,
            "completed": done,
            "total": len(steps),
            "duration_ms": int((time.time() - started) * 1000),
            **extra,
        }


def _secret_var(step: Step) -> str:
    """Variable name a password step reads its value from."""
    if step.value and _VAR.fullmatch(step.value.strip()):
        return _VAR.findall(step.value)[0]
    return "password"


def _short(exc: Exception) -> str:
    return str(exc).split("\n", 1)[0][:160]
