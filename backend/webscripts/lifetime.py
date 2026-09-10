"""Making sure the backend never outlives the app that started it.

A windowed PyInstaller build has no console and no window, so a backend that
keeps running after the app is gone is invisible: it does not show up where a
user looks in Task Manager, it holds its own .exe open so the folder cannot be
deleted, and it keeps port 8765 for the next start.

Two independent guards stop that from happening:

* the **parent watch** — the app passes its process id, and the backend exits
  as soon as that process is gone (closed, crashed, or killed);
* the **client watch** — if no UI has been connected for a while and nothing
  is running, the backend exits by itself.

Both call the same shutdown, which closes any browser first.
"""

from __future__ import annotations

import os
import sys
import threading
import time
from typing import Callable

# How often the parent is checked, and how long the backend waits for a UI to
# come back before giving up on it.
PARENT_POLL = 2.0
CLIENT_GRACE = 90.0


def parent_is_alive(pid: int) -> bool:
    """Is that process still running?"""
    if pid <= 0:
        return True
    if sys.platform == "win32":
        import ctypes

        # SYNCHRONIZE is enough to ask about a process we do not own.
        handle = ctypes.windll.kernel32.OpenProcess(0x00100000, False, pid)
        if not handle:
            return False
        try:
            # WAIT_OBJECT_0 means the process has signalled, i.e. it exited.
            return ctypes.windll.kernel32.WaitForSingleObject(handle, 0) != 0
        finally:
            ctypes.windll.kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class Lifetime:
    """Owns the two watchdogs and the one way out."""

    def __init__(
        self,
        shutdown: Callable[[], None],
        parent_pid: int = 0,
        client_grace: float = CLIENT_GRACE,
    ) -> None:
        self.shutdown = shutdown
        self.parent_pid = parent_pid
        self.client_grace = client_grace
        self.clients = 0
        self._seen_client = False
        self._alone_since: float | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self.reason = ""

    # ------------------------------------------------------------- clients

    def client_connected(self) -> None:
        self.clients += 1
        self._seen_client = True
        self._alone_since = None

    def client_gone(self) -> None:
        self.clients = max(0, self.clients - 1)
        if self.clients == 0:
            self._alone_since = time.time()

    # ------------------------------------------------------------ watching

    def start(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(
            target=self._watch, name="webscripts-lifetime", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _watch(self) -> None:
        while not self._stop.wait(PARENT_POLL):
            reason = self.should_exit(busy=self.busy())
            if reason:
                self.reason = reason
                self.shutdown()
                return

    # A hook the server replaces; without it the client watch never fires.
    busy: Callable[[], bool] = staticmethod(lambda: False)

    def should_exit(self, busy: bool, now: float | None = None) -> str:
        """Why the backend should stop — empty string means "keep running"."""
        if self.parent_pid and not parent_is_alive(self.parent_pid):
            return "the app that started it is gone"
        if busy or self.clients or not self._seen_client:
            return ""
        if self._alone_since is None:
            return ""
        waited = (now or time.time()) - self._alone_since
        if waited >= self.client_grace:
            return f"no UI for {int(waited)}s"
        return ""


def exit_now(code: int = 0) -> None:
    """Leave immediately, without waiting for uvicorn to unwind."""
    sys.stdout.flush() if sys.stdout else None
    sys.stderr.flush() if sys.stderr else None
    os._exit(code)
