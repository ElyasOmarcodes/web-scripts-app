"""HTTP + WebSocket API consumed by the Flutter desktop UI."""

from __future__ import annotations

import asyncio
import platform
import threading
from typing import Any

from fastapi import Body, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import browsers, config
from .accounts import AccountLimitReached, AccountStore
from .lifetime import Lifetime, exit_now
from .machine import estimate, machine
from .models import Script, Step, Variable
from .session import SessionBusy, SessionManager
from .settings import Settings, SettingsStore
from .storage import Storage
from .tasks import TaskStore

storage = Storage()
settings_store = SettingsStore()
account_store = AccountStore()
task_store = TaskStore()
manager = SessionManager(storage, settings_store, account_store, task_store)

# Filled in by main(); the default one never exits on its own, which is what a
# developer running `python run_server.py` by hand wants.
lifetime = Lifetime(shutdown=lambda: None)

app = FastAPI(title="WebScripts API", version=config.VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ------------------------------------------------------------------ schemas


class RecordStart(BaseModel):
    name: str = "نوی سکریپټ"
    url: str = ""
    capture_scroll: bool | None = None
    script_id: str | None = None
    browser: str | None = None
    # Record as this saved account, so the site opens already signed in.
    account_id: str | None = None


class RunRequest(BaseModel):
    variables: dict[str, str] = Field(default_factory=dict)
    # Omitted values fall back to the saved settings.
    speed: float | None = None
    headless: bool | None = None
    keep_open: bool | None = None
    browser: str | None = None
    # Which saved account's session to run as.
    account_id: str | None = None


class LoginStart(BaseModel):
    category: str
    label: str = ""
    browser: str | None = None


class AccountPatch(BaseModel):
    label: str | None = None


class CategoryPatch(BaseModel):
    max_accounts: int | None = None


class TaskUpsert(BaseModel):
    """Everything a task holds; every field is optional on a PATCH."""

    name: str | None = None
    script_id: str | None = None
    account_ids: list[str] | None = None
    concurrency: int | None = Field(default=None, ge=1, le=32)
    browser: str | None = None
    speed: float | None = None
    headless: bool | None = None
    keep_open: bool | None = None
    stop_on_error: bool | None = None
    gap_seconds: float | None = Field(default=None, ge=0, le=600)
    variables: dict[str, str] | None = None
    note: str | None = None


class CookieCheck(BaseModel):
    # Empty means "every account".
    account_ids: list[str] | None = None


class TaskRun(BaseModel):
    # Continue from where it stopped instead of starting every account again.
    resume: bool = False


class ScriptUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    start_url: str | None = None
    steps: list[Step] | None = None
    variables: list[Variable] | None = None
    # This script's own random pause between two actions, in milliseconds.
    gap_min_ms: int | None = Field(default=None, ge=0, le=60_000)
    gap_max_ms: int | None = Field(default=None, ge=0, le=120_000)


# ------------------------------------------------------------------- routes


@app.get("/api/health")
def health() -> dict[str, Any]:
    try:
        active = browsers.resolve(settings_store.load().browser).to_dict()
    except browsers.BrowserNotFound as exc:
        active = {"error": str(exc)}
    return {
        "ok": True,
        "version": config.VERSION,
        "platform": platform.system(),
        "home": str(config.BASE_DIR),
        "profile": str(config.PROFILE_DIR),
        "state": manager.state,
        "browser": active,
    }


# ------------------------------------------------------------ settings


@app.get("/api/settings")
def get_settings() -> dict:
    return settings_store.load().model_dump()


@app.put("/api/settings")
def put_settings(payload: dict = Body(...)) -> dict:
    try:
        return settings_store.update(payload).model_dump()
    except Exception as exc:  # noqa: BLE001 - validation message goes to the UI
        raise HTTPException(400, f"ناسم تنظیم: {exc}") from None


@app.post("/api/settings/reset")
def reset_settings() -> dict:
    return settings_store.save(Settings()).model_dump()


@app.get("/api/browsers")
def list_browsers(refresh: bool = False) -> dict:
    found = browsers.detect(refresh=refresh)
    preferred = settings_store.load().browser
    try:
        active = browsers.resolve(preferred).id
    except browsers.BrowserNotFound:
        active = None
    return {
        "browsers": [b.to_dict() for b in found],
        "selected": preferred,
        "active": active,
    }


@app.get("/api/scripts")
def list_scripts() -> list[dict[str, Any]]:
    return [script.summary() for script in storage.list()]


@app.post("/api/scripts")
def create_script(payload: ScriptUpdate = Body(default_factory=ScriptUpdate)) -> dict:
    script = Script(
        name=payload.name or "نوی سکریپټ",
        description=payload.description or "",
        start_url=payload.start_url or "",
        steps=payload.steps or [],
        variables=payload.variables or [],
    )
    return storage.save(script).model_dump()


@app.get("/api/scripts/{script_id}")
def get_script(script_id: str) -> dict:
    script = storage.get(script_id)
    if script is None:
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    return script.model_dump()


@app.put("/api/scripts/{script_id}")
def update_script(script_id: str, payload: ScriptUpdate) -> dict:
    script = storage.get(script_id)
    if script is None:
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    # Assign the parsed objects (not dumped dicts) so the stored model keeps
    # its proper types. A field sent as null is a deliberate "unset me" —
    # that is how a script goes back to the app-wide pacing.
    clearable = {"gap_min_ms", "gap_max_ms"}
    for field in payload.model_fields_set:
        value = getattr(payload, field)
        if value is not None or field in clearable:
            setattr(script, field, value)
    return storage.save(script).model_dump()


@app.delete("/api/scripts/{script_id}")
def delete_script(script_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("script_id") == script_id:
        raise HTTPException(409, "دا سکریپټ اوس روان دی")
    if not storage.delete(script_id):
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    task_store.forget_script(script_id)
    return {"ok": True}


@app.post("/api/scripts/{script_id}/run")
def run_script(script_id: str, payload: RunRequest) -> dict:
    try:
        return manager.start_run(
            script_id,
            variables=payload.variables,
            speed=payload.speed,
            headless=payload.headless,
            keep_open=payload.keep_open,
            browser=payload.browser,
            account_id=payload.account_id,
        )
    except KeyError:
        raise HTTPException(404, "سکریپټ ونه موندل شو") from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None


# ------------------------------------------------------------ accounts


@app.get("/api/accounts")
def list_accounts() -> dict:
    return account_store.overview()


@app.post("/api/accounts/login/start")
def account_login_start(payload: LoginStart) -> dict:
    try:
        return manager.start_login(
            payload.category, label=payload.label, browser=payload.browser
        )
    except KeyError:
        raise HTTPException(404, "کټګوري ونه موندل شوه") from None
    except AccountLimitReached as exc:
        raise HTTPException(409, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/accounts/login/finish")
def account_login_finish() -> dict:
    try:
        return manager.finish_login()
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.patch("/api/accounts/{account_id}")
def patch_account(account_id: str, payload: AccountPatch) -> dict:
    account = account_store.update(account_id, label=payload.label)
    if account is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    return account.summary()


@app.delete("/api/accounts/{account_id}")
def delete_account(account_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("account_id") == account_id:
        raise HTTPException(409, "دا اکاونټ اوس کارېږي")
    if not account_store.delete(account_id):
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    task_store.forget_account(account_id)
    return {"ok": True}


@app.patch("/api/accounts/categories/{category_id}")
def patch_category(category_id: str, payload: CategoryPatch) -> dict:
    if payload.max_accounts is None:
        raise HTTPException(400, "max_accounts اړین دی")
    category = account_store.set_limit(category_id, payload.max_accounts)
    if category is None:
        raise HTTPException(404, "کټګوري ونه موندل شوه")
    used = account_store.count(category_id)
    if used > category.max_accounts:
        raise HTTPException(
            400,
            f"اوس مهال {used} اکاونټه شته — حد له دې کم نه شي کېدای.",
        )
    return {**category.model_dump(), "used": used}


# ------------------------------------------------------------------- tasks


@app.get("/api/system")
def system_info(windows: int = 1, headless: bool = False) -> dict:
    """What the machine is, and what N browser windows would cost on it."""
    return {"machine": machine().to_dict(), "estimate": estimate(windows, headless)}


@app.post("/api/accounts/check")
def check_accounts(payload: CookieCheck) -> dict:
    try:
        return manager.start_cookie_check(payload.account_ids)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.get("/api/tasks/{task_id}/log")
def task_log(task_id: str, limit: int = 300) -> dict:
    if task_store.get(task_id) is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return {"entries": task_store.read_log(task_id, limit=limit)}


@app.delete("/api/tasks/{task_id}/log")
def clear_task_log(task_id: str) -> dict:
    task_store.clear_log(task_id)
    return {"ok": True}


@app.get("/api/tasks")
def list_tasks() -> dict:
    return {
        "tasks": [t.summary() for t in task_store.list()],
        "overview": task_store.overview(),
    }


@app.post("/api/tasks")
def create_task(payload: TaskUpsert) -> dict:
    fields = {k: v for k, v in payload.model_dump().items() if v is not None}
    return task_store.create(**fields).summary()


@app.get("/api/tasks/{task_id}")
def get_task(task_id: str) -> dict:
    task = task_store.get(task_id)
    if task is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return task.summary()


@app.patch("/api/tasks/{task_id}")
def patch_task(task_id: str, payload: TaskUpsert) -> dict:
    changes = {
        key: value
        for key, value in payload.model_dump().items()
        if key in payload.model_fields_set
    }
    task = task_store.update(task_id, **changes)
    if task is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return task.summary()


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("task_id") == task_id:
        raise HTTPException(409, "دا کار اوس روان دی")
    if not task_store.delete(task_id):
        raise HTTPException(404, "کار ونه موندل شو")
    return {"ok": True}


@app.post("/api/tasks/{task_id}/run")
def run_task(task_id: str, payload: TaskRun) -> dict:
    try:
        return manager.start_task(task_id, resume=payload.resume)
    except KeyError:
        raise HTTPException(404, "کار ونه موندل شو") from None
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/record/start")
def record_start(payload: RecordStart) -> dict:
    try:
        return manager.start_recording(
            name=payload.name,
            url=payload.url,
            capture_scroll=payload.capture_scroll,
            script_id=payload.script_id,
            browser=payload.browser,
            account_id=payload.account_id,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/record/stop")
def record_stop() -> dict:
    try:
        return manager.stop_recording()
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/session/stop")
def session_stop() -> dict:
    return manager.stop()


@app.get("/api/session")
def session_status() -> dict:
    return manager.status()


@app.get("/api/events")
def events(limit: int = 200) -> list[dict]:
    return manager.bus.history(limit)


@app.post("/api/shutdown")
def shutdown() -> dict:
    """Stop the browser and end the process.

    The app calls this as its window closes. Without it the backend would keep
    running with no window anywhere — invisible, holding its own file open.
    """
    manager.shutdown()
    threading.Timer(0.25, exit_now).start()
    return {"ok": True}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=1000)

    def on_event(event: dict) -> None:
        # Called from the worker thread: hop back onto the event loop.
        loop.call_soon_threadsafe(_offer, queue, event)

    unsubscribe = manager.bus.subscribe(on_event)
    lifetime.client_connected()
    try:
        for past in manager.bus.history(50):
            await websocket.send_json(past)
        while True:
            event = await queue.get()
            await websocket.send_json(event)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        unsubscribe()
        lifetime.client_gone()


def _offer(queue: asyncio.Queue, event: dict) -> None:
    try:
        queue.put_nowait(event)
    except asyncio.QueueFull:
        pass


def attach_log_streams() -> None:
    """Give the process somewhere to write when there is no console.

    A PyInstaller *windowed* build has no console at all: sys.stdout and
    sys.stderr are None, and uvicorn's very first log line would raise. Point
    them at a file under the app directory instead, which also gives the user
    something to send when something goes wrong.
    """
    import sys

    if sys.stdout is not None and sys.stderr is not None:
        return
    config.ensure_dirs()
    handle = open(  # noqa: SIM115 - lives for the process lifetime
        config.LOGS_DIR / "backend.log", "a", encoding="utf-8", buffering=1
    )
    if sys.stdout is None:
        sys.stdout = handle
    if sys.stderr is None:
        sys.stderr = handle


def main(argv: list[str] | None = None) -> None:
    import argparse
    import os
    import uvicorn

    parser = argparse.ArgumentParser(description="WebScripts backend")
    parser.add_argument(
        "--parent-pid",
        type=int,
        default=int(os.environ.get("WEBSCRIPTS_PARENT_PID") or 0),
        help="exit as soon as this process (the desktop app) is gone",
    )
    parser.add_argument("--host", default=config.HOST)
    parser.add_argument("--port", type=int, default=config.PORT)
    args = parser.parse_args(argv)

    config.ensure_dirs()
    attach_log_streams()

    global lifetime
    lifetime = Lifetime(shutdown=_shutdown_and_exit, parent_pid=args.parent_pid)
    lifetime.busy = lambda: manager.state != "idle"
    lifetime.start()

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


def _shutdown_and_exit() -> None:
    print(f"webscripts: shutting down — {lifetime.reason}")
    manager.shutdown()
    exit_now()


if __name__ == "__main__":
    main()
