"""Application paths and runtime settings.

Everything the app writes (scripts, logs, the dedicated Edge profile) lives
under a single base directory so the user can back it up or wipe it easily.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

APP_NAME = "WebScripts"
VERSION = "0.1.0"


def _default_base_dir() -> Path:
    override = os.environ.get("WEBSCRIPTS_HOME")
    if override:
        return Path(override).expanduser()
    if sys.platform.startswith("win"):
        root = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(root) / APP_NAME
    xdg = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(xdg) / APP_NAME


BASE_DIR = _default_base_dir()
SCRIPTS_DIR = BASE_DIR / "scripts"
LOGS_DIR = BASE_DIR / "logs"
SHOTS_DIR = BASE_DIR / "screenshots"

# A dedicated browser profile keeps the user logged in between a recording
# session and later replays (e.g. Facebook stays signed in).
PROFILE_DIR = BASE_DIR / "edge-profile"

# Saved website accounts: one browser profile and one cookie file each.
ACCOUNTS_DIR = BASE_DIR / "accounts"

HOST = os.environ.get("WEBSCRIPTS_HOST", "127.0.0.1")
PORT = int(os.environ.get("WEBSCRIPTS_PORT", "8765"))

# How long the player waits for an element before failing a step.
STEP_TIMEOUT = float(os.environ.get("WEBSCRIPTS_STEP_TIMEOUT", "15"))
# Poll interval of the recorder loop, in seconds.
RECORDER_POLL = float(os.environ.get("WEBSCRIPTS_RECORDER_POLL", "0.25"))


def ensure_dirs() -> None:
    for path in (
        BASE_DIR,
        SCRIPTS_DIR,
        LOGS_DIR,
        SHOTS_DIR,
        PROFILE_DIR,
        ACCOUNTS_DIR,
        ACCOUNTS_DIR / "cookies",
        ACCOUNTS_DIR / "profiles",
    ):
        path.mkdir(parents=True, exist_ok=True)
