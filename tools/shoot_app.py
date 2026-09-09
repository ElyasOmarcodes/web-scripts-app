"""Run the real WebScripts desktop app and photograph every screen.

Starts the Python backend against a demo data directory, launches the built
Flutter binary on a virtual X display, drives it with real mouse clicks
(xdotool) and captures the actual window with `import`.

    python3 tools/shoot_app.py [--out docs/screenshots] [--dark]
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "frontend/build/linux/x64/debug/bundle/web_scripts"
DISPLAY = ":99"
SCREEN = (1400, 900)
WINDOW = (1240, 800)

# Sidebar rows, in the order the app draws them (RTL: x is near the right edge).
# Hit points read off the running window at 1240x800.
RUN_BUTTON = (936, 342)       # first script card's "چلول"
FACEBOOK_CARD = (250, 600)    # the 7-step Facebook script
ADD_ACCOUNT = (198, 101)      # "نوی اکاونټ زیاتول"

SIDEBAR_X = 1128
SIDEBAR_Y = {
    "dashboard": 142,
    "scripts": 173,
    "accounts": 204,
    "recorder": 235,
    "activity": 266,
    "settings": 328,
    "help": 359,
}


class Stage:
    """Owns the virtual display, the backend and the app process."""

    def __init__(self, home: Path, dark: bool = False) -> None:
        self.home = home
        self.dark = dark
        self.procs: list[subprocess.Popen] = []
        self.env = {
            **os.environ,
            "DISPLAY": DISPLAY,
            "WEBSCRIPTS_HOME": str(home),
            # Software rendering: there is no GPU on a build machine.
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "GDK_BACKEND": "x11",
        }

    # ------------------------------------------------------------- lifecycle

    def start(self) -> None:
        self._spawn(
            ["Xvfb", DISPLAY, "-screen", "0", f"{SCREEN[0]}x{SCREEN[1]}x24", "-nolisten", "tcp"],
            wait=1.5,
        )
        # Without a window manager the app never takes input focus, so the
        # synthetic clicks below would go nowhere.
        self._spawn(["openbox"], wait=1.0)
        self._spawn(
            [sys.executable, "run_server.py"],
            cwd=ROOT / "backend",
            wait=0,
        )
        self._wait_for_backend()
        self._spawn([str(APP)], wait=0)
        self._wait_for_window()

    def _spawn(self, command: list[str], cwd: Path | None = None, wait: float = 0):
        process = subprocess.Popen(
            command,
            cwd=str(cwd) if cwd else None,
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.procs.append(process)
        if wait:
            time.sleep(wait)
        return process

    def _wait_for_backend(self, timeout: float = 45) -> None:
        import urllib.request

        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(
                    "http://127.0.0.1:8765/api/health", timeout=2
                ) as response:
                    if response.status == 200:
                        print("  backend is up")
                        return
            except Exception:  # noqa: BLE001
                time.sleep(0.5)
        raise RuntimeError("backend did not start")

    def _wait_for_window(self, timeout: float = 90) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            found = subprocess.run(
                ["xdotool", "search", "--name", "WebScripts"],
                env=self.env, capture_output=True, text=True,
            )
            if found.stdout.strip():
                self.window = found.stdout.strip().splitlines()[-1]
                time.sleep(4)  # let the first frame settle
                subprocess.run(
                    ["xdotool", "windowsize", self.window, str(WINDOW[0]), str(WINDOW[1])],
                    env=self.env, check=False,
                )
                subprocess.run(
                    ["xdotool", "windowmove", self.window,
                     str((SCREEN[0] - WINDOW[0]) // 2), str((SCREEN[1] - WINDOW[1]) // 2)],
                    env=self.env, check=False,
                )
                subprocess.run(["xdotool", "windowactivate", "--sync", self.window],
                               env=self.env, check=False)
                subprocess.run(["xdotool", "windowfocus", self.window],
                               env=self.env, check=False)
                time.sleep(1.5)
                self.origin = self._geometry()
                print(f"  app window {self.window} at {self.origin}")
                return
            time.sleep(1)
        raise RuntimeError("the app window never appeared")

    def stop(self) -> None:
        for process in reversed(self.procs):
            try:
                process.send_signal(signal.SIGTERM)
                process.wait(timeout=5)
            except Exception:  # noqa: BLE001
                try:
                    process.kill()
                except Exception:  # noqa: BLE001
                    pass

    # ---------------------------------------------------------------- acting

    def _geometry(self) -> tuple[int, int]:
        """Where the window sits on screen, so clicks can use absolute coords."""
        result = subprocess.run(
            ["xdotool", "getwindowgeometry", "--shell", self.window],
            env=self.env, capture_output=True, text=True,
        )
        values = {}
        for line in result.stdout.splitlines():
            if "=" in line:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip()
        return int(values.get("X", 0)), int(values.get("Y", 0))

    def click(self, *args, settle: float = 1.2) -> None:
        x, y = args[0] if len(args) == 1 else args
        self.move(x, y, settle=0.15)
        subprocess.run(["xdotool", "click", "1"], env=self.env, check=False)
        time.sleep(settle)

    def move(self, x: int, y: int, settle: float = 0.4) -> None:
        origin_x, origin_y = getattr(self, "origin", (0, 0))
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(origin_x + x), str(origin_y + y)],
            env=self.env, check=False,
        )
        time.sleep(settle)

    def key(self, key: str, settle: float = 0.8) -> None:
        subprocess.run(["xdotool", "key", "--window", self.window, key],
                       env=self.env, check=False)
        time.sleep(settle)

    def go(self, page: str) -> None:
        self.click(SIDEBAR_X, SIDEBAR_Y[page])
        time.sleep(0.8)

    def shot(self, name: str, out: Path) -> Path:
        out.mkdir(parents=True, exist_ok=True)
        target = out / f"{name}.png"
        subprocess.run(
            ["import", "-window", self.window, "-quality", "95", str(target)],
            env=self.env, check=True,
        )
        # Park the pointer so it never leaves a hover highlight in the next shot.
        self.move(620, 760, settle=0.1)
        print(f"  {target.name:<30} {target.stat().st_size // 1024} KB")
        return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="docs/screenshots")
    parser.add_argument("--home", default="/tmp/wsdemo")
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()

    if not APP.exists():
        print(f"build the app first: flutter build linux --debug ({APP})")
        return 1

    out = ROOT / args.out
    home = Path(args.home)
    if not home.exists():
        print(f"seed the demo data first: WEBSCRIPTS_HOME={home} python3 tools/seed_demo.py")
        return 1

    stage = Stage(home, dark=args.dark)
    try:
        print("== starting ==")
        stage.start()

        print("== capturing ==")
        stage.go("dashboard")
        stage.shot("01-dashboard", out)

        stage.go("scripts")
        stage.shot("02-scripts", out)

        # Run a script: the account picker comes up first.
        stage.click(RUN_BUTTON, settle=1.6)
        stage.shot("03-run-as-account", out)
        stage.key("Escape", settle=0.8)

        # Open the Facebook script (bottom-left card) to show its steps.
        stage.click(FACEBOOK_CARD, settle=1.8)
        stage.shot("04-script-detail", out)
        stage.key("Escape", settle=0.6)

        stage.go("accounts")
        stage.shot("05-accounts", out)

        # "Add account" → the service picker sheet.
        stage.click(ADD_ACCOUNT, settle=1.6)
        stage.shot("06-add-account", out)
        stage.key("Escape", settle=1.0)

        stage.go("recorder")
        stage.shot("07-recorder", out)

        stage.go("settings")
        stage.shot("08-settings", out)

        stage.go("activity")
        stage.shot("09-activity", out)

        stage.go("help")
        stage.shot("10-help", out)

        print("== done ==")
        return 0
    finally:
        stage.stop()
        # Xvfb leaves a lock behind when it is killed.
        shutil.rmtree(f"/tmp/.X11-unix/X{DISPLAY[1:]}", ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
