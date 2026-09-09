"""Session manager: owns the browser and runs recording / replay in a thread.

Only one browser session is active at a time, which keeps the Edge profile
(and the user's logins) free of conflicts.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from typing import Any, Callable

from .driver import BrowserError, create_driver
from .settings import Settings, SettingsStore
from .models import Script, Step, Variable
from .player import Player
from .recorder import Recorder
from .storage import Storage

IDLE = "idle"
RECORDING = "recording"
PLAYING = "playing"


class SessionBusy(RuntimeError):
    pass


class EventBus:
    """Fan-out of log/progress events to any number of listeners."""

    def __init__(self, history: int = 400) -> None:
        self._subs: list[Callable[[dict], None]] = []
        self._lock = threading.Lock()
        self._history: deque[dict] = deque(maxlen=history)

    def publish(self, event: dict) -> None:
        event = {"ts": int(time.time() * 1000), **event}
        with self._lock:
            self._history.append(event)
            subs = list(self._subs)
        for sub in subs:
            try:
                sub(event)
            except Exception:  # noqa: BLE001 - a broken listener must not stop others
                pass

    def subscribe(self, fn: Callable[[dict], None]) -> Callable[[], None]:
        with self._lock:
            self._subs.append(fn)

        def unsubscribe() -> None:
            with self._lock:
                if fn in self._subs:
                    self._subs.remove(fn)

        return unsubscribe

    def history(self, limit: int = 200) -> list[dict]:
        with self._lock:
            return list(self._history)[-limit:]


class SessionManager:
    def __init__(
        self,
        storage: Storage | None = None,
        settings: SettingsStore | None = None,
    ) -> None:
        self.storage = storage or Storage()
        self.settings = settings or SettingsStore()
        self.bus = EventBus()
        self.state: str = IDLE
        self.detail: dict[str, Any] = {}
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._driver = None
        self._recorder: Recorder | None = None
        self._last_script_id: str | None = None
        self._last_result: dict | None = None

    # ---------------------------------------------------------------- status

    def status(self) -> dict:
        return {
            "state": self.state,
            "detail": self.detail,
            "last_script_id": self._last_script_id,
            "last_result": self._last_result,
        }

    def log(self, level: str, message: str) -> None:
        self.bus.publish({"type": "log", "level": level, "message": message})

    # ------------------------------------------------------------- recording

    def start_recording(
        self,
        name: str,
        url: str,
        capture_scroll: bool | None = None,
        script_id: str | None = None,
        browser: str | None = None,
    ) -> dict:
        prefs = self.settings.load()
        capture_scroll = (
            prefs.capture_scroll if capture_scroll is None else capture_scroll
        )
        browser = browser or prefs.browser
        with self._lock:
            if self.state != IDLE:
                raise SessionBusy(f"یوه بله چاره روانه ده: {self.state}")
            self.state = RECORDING
            self._stop.clear()
            self.detail = {"name": name, "url": url, "steps": 0}
            self._last_result = None

        self._thread = threading.Thread(
            target=self._record_worker,
            args=(name, url, capture_scroll, script_id, browser, prefs),
            name="webscripts-recorder",
            daemon=True,
        )
        self._thread.start()
        return self.status()

    def _record_worker(
        self,
        name: str,
        url: str,
        capture_scroll: bool,
        script_id: str | None,
        browser: str,
        prefs: Settings,
    ) -> None:
        steps: list[Step] = []
        try:
            self.log("info", "براوزر پیلېږي…")
            self._driver = create_driver(
                headless=False, use_profile=prefs.use_profile, browser=browser
            )
            self.log("info", "ثبتول پیل شول. په براوزر کې خپل کار وکړئ.")
            self.bus.publish({"type": "recording_started", "name": name, "url": url})

            recorder = Recorder(
                self._driver,
                on_step=self._on_recorded_step,
                on_log=self.log,
                capture_scroll=capture_scroll,
            )
            self._recorder = recorder
            recorder.start(url)
            steps = recorder.loop(self._stop.is_set)
        except BrowserError as exc:
            self.log("error", str(exc))
            self.bus.publish({"type": "recording_failed", "message": str(exc)})
        except Exception as exc:  # noqa: BLE001
            self.log("error", f"د ثبتولو تېروتنه: {exc}")
            self.bus.publish({"type": "recording_failed", "message": str(exc)})
        finally:
            script = self._save_recording(name, url, steps, script_id)
            self._quit_driver()
            self._recorder = None
            self.state = IDLE
            self.detail = {}
            if script is not None:
                self._last_script_id = script.id
                self.bus.publish(
                    {"type": "recording_saved", "script": script.summary()}
                )
                self.log(
                    "info",
                    f"سکریپټ خوندي شو: «{script.name}» ({len(script.steps)} ګامه)",
                )

    def _on_recorded_step(self, step: Step) -> None:
        self.detail["steps"] = int(self.detail.get("steps", 0)) + 1
        self.bus.publish(
            {
                "type": "step_recorded",
                "index": self.detail["steps"],
                "message": step.describe(),
                "step": step.model_dump(),
            }
        )

    def _save_recording(
        self, name: str, url: str, steps: list[Step], script_id: str | None
    ) -> Script | None:
        if not steps:
            self.log("warn", "هېڅ ګام ثبت نه شو — سکریپټ خوندي نه شو.")
            return None
        script = (self.storage.get(script_id) if script_id else None) or Script()
        script.name = name or script.name
        script.start_url = url or script.start_url
        script.steps = steps
        script.variables = _collect_variables(steps)
        return self.storage.save(script)

    def stop_recording(self, timeout: float = 30.0) -> dict:
        if self.state != RECORDING:
            raise SessionBusy("اوس مهال ثبتول روان نه دي.")
        self._stop.set()
        self._join(timeout)
        script = (
            self.storage.get(self._last_script_id) if self._last_script_id else None
        )
        return {"status": self.status(), "script": script.model_dump() if script else None}

    # ---------------------------------------------------------------- replay

    def start_run(
        self,
        script_id: str,
        variables: dict[str, str] | None = None,
        speed: float | None = None,
        headless: bool | None = None,
        keep_open: bool | None = None,
        browser: str | None = None,
    ) -> dict:
        prefs = self.settings.load()
        speed = prefs.speed if speed is None else speed
        headless = prefs.headless if headless is None else headless
        keep_open = prefs.keep_open if keep_open is None else keep_open
        browser = browser or prefs.browser
        script = self.storage.get(script_id)
        if script is None:
            raise KeyError(script_id)
        missing = [
            v.name
            for v in script.variables
            if v.secret and not (variables or {}).get(v.name)
        ]
        if missing:
            raise ValueError(f"دا ارزښتونه اړین دي: {', '.join(missing)}")

        with self._lock:
            if self.state != IDLE:
                raise SessionBusy(f"یوه بله چاره روانه ده: {self.state}")
            self.state = PLAYING
            self._stop.clear()
            self.detail = {"script_id": script.id, "name": script.name}
            self._last_result = None

        self._thread = threading.Thread(
            target=self._play_worker,
            args=(
                script,
                dict(variables or {}),
                speed,
                headless,
                keep_open,
                browser,
                prefs,
            ),
            name="webscripts-player",
            daemon=True,
        )
        self._thread.start()
        return self.status()

    def _play_worker(
        self,
        script: Script,
        variables: dict[str, str],
        speed: float,
        headless: bool,
        keep_open: bool,
        browser: str,
        prefs: Settings,
    ) -> None:
        result: dict = {"status": "failed", "script_id": script.id}
        try:
            self.log("info", f"«{script.name}» پیلېږي…")
            self._driver = create_driver(
                headless=headless, use_profile=prefs.use_profile, browser=browser
            )
            self.bus.publish(
                {
                    "type": "run_started",
                    "script_id": script.id,
                    "name": script.name,
                    "total": len([s for s in script.steps if s.enabled]),
                }
            )
            player = Player(
                self._driver,
                on_event=self.bus.publish,
                should_stop=self._stop.is_set,
                speed=speed,
                step_timeout=prefs.step_timeout,
            )
            if script.start_url and not _starts_with_goto(script):
                self._driver.get(script.start_url)
            result = player.play(script, variables)
        except BrowserError as exc:
            result = {"status": "failed", "script_id": script.id, "error": str(exc)}
            self.log("error", str(exc))
        except Exception as exc:  # noqa: BLE001
            result = {"status": "failed", "script_id": script.id, "error": str(exc)}
            self.log("error", f"د چلولو تېروتنه: {exc}")
        finally:
            if not keep_open:
                self._quit_driver()
            self.state = IDLE
            self.detail = {}
            self._last_result = result
            self._record_run_outcome(script.id, result)
            self.bus.publish({"type": "run_finished", **result})
            self.log(
                "info" if result.get("status") == "ok" else "error",
                _run_summary(result),
            )

    def _record_run_outcome(self, script_id: str, result: dict) -> None:
        script = self.storage.get(script_id)
        if script is None:
            return
        script.last_run_at = int(time.time() * 1000)
        script.last_run_ok = result.get("status") == "ok"
        self.storage.save(script)

    # ----------------------------------------------------------------- misc

    def stop(self, timeout: float = 30.0) -> dict:
        self._stop.set()
        self._join(timeout)
        return self.status()

    def _join(self, timeout: float) -> None:
        thread = self._thread
        if thread and thread.is_alive():
            thread.join(timeout)

    def _quit_driver(self) -> None:
        driver = self._driver
        self._driver = None
        if driver is None:
            return
        try:
            driver.quit()
        except Exception:  # noqa: BLE001
            pass


def _starts_with_goto(script: Script) -> bool:
    for step in script.steps:
        if step.enabled:
            return step.action == "goto"
    return False


def _collect_variables(steps: list[Step]) -> list[Variable]:
    """Turn recorded password fields into named variables."""
    variables: list[Variable] = []
    index = 0
    for step in steps:
        if step.action == "type" and step.secret:
            index += 1
            name = "password" if index == 1 else f"password_{index}"
            step.value = f"{{{{{name}}}}}"
            variables.append(
                Variable(
                    name=name,
                    label=step.label or "پټنوم",
                    secret=True,
                )
            )
    return variables


def _run_summary(result: dict) -> str:
    status = result.get("status")
    if status == "ok":
        return (
            f"بریالی! {result.get('completed', 0)} ګامه ترسره شول "
            f"({result.get('duration_ms', 0) / 1000:.1f}s)"
        )
    if status == "stopped":
        return f"ودرول شو په {result.get('completed', 0)} ګام کې."
    return f"ناکام: {result.get('error') or 'نامعلومه تېروتنه'}"


__all__ = ["SessionManager", "SessionBusy", "EventBus", "IDLE", "RECORDING", "PLAYING"]
