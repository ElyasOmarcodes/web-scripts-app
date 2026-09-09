"""HTTP + WebSocket API consumed by the Flutter desktop UI."""

from __future__ import annotations

import asyncio
import platform
from typing import Any

from fastapi import Body, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import config
from .models import Script, Step, Variable
from .session import SessionBusy, SessionManager
from .storage import Storage

storage = Storage()
manager = SessionManager(storage)

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
    capture_scroll: bool = False
    script_id: str | None = None


class RunRequest(BaseModel):
    variables: dict[str, str] = Field(default_factory=dict)
    speed: float = 1.0
    headless: bool = False
    keep_open: bool = False


class ScriptUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    start_url: str | None = None
    steps: list[Step] | None = None
    variables: list[Variable] | None = None


# ------------------------------------------------------------------- routes


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "version": config.VERSION,
        "platform": platform.system(),
        "home": str(config.BASE_DIR),
        "profile": str(config.PROFILE_DIR),
        "state": manager.state,
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
    # its proper types.
    for field in payload.model_fields_set:
        value = getattr(payload, field)
        if value is not None:
            setattr(script, field, value)
    return storage.save(script).model_dump()


@app.delete("/api/scripts/{script_id}")
def delete_script(script_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("script_id") == script_id:
        raise HTTPException(409, "دا سکریپټ اوس روان دی")
    if not storage.delete(script_id):
        raise HTTPException(404, "سکریپټ ونه موندل شو")
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
        )
    except KeyError:
        raise HTTPException(404, "سکریپټ ونه موندل شو") from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None


@app.post("/api/record/start")
def record_start(payload: RecordStart) -> dict:
    try:
        return manager.start_recording(
            name=payload.name,
            url=payload.url,
            capture_scroll=payload.capture_scroll,
            script_id=payload.script_id,
        )
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


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=1000)

    def on_event(event: dict) -> None:
        # Called from the worker thread: hop back onto the event loop.
        loop.call_soon_threadsafe(_offer, queue, event)

    unsubscribe = manager.bus.subscribe(on_event)
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


def _offer(queue: asyncio.Queue, event: dict) -> None:
    try:
        queue.put_nowait(event)
    except asyncio.QueueFull:
        pass


def main() -> None:
    import uvicorn

    config.ensure_dirs()
    uvicorn.run(app, host=config.HOST, port=config.PORT, log_level="info")


if __name__ == "__main__":
    main()
