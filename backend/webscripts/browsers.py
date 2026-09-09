"""Detect the browsers that are really installed on this machine.

Only the Chromium family is driveable by this app (they share the same
WebDriver options and the `--user-data-dir` profile flag). Firefox is reported
when found, but flagged as unsupported rather than silently hidden.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

CHROMIUM = "chromium"
GECKO = "gecko"


@dataclass
class BrowserInfo:
    id: str
    name: str
    family: str
    path: str = ""
    version: str = ""
    installed: bool = False
    supported: bool = True

    def to_dict(self) -> dict:
        return asdict(self)


# id -> (display name, family, windows relative paths, posix executables)
CATALOG: dict[str, tuple[str, str, list[str], list[str]]] = {
    "edge": (
        "Microsoft Edge",
        CHROMIUM,
        [r"Microsoft\Edge\Application\msedge.exe"],
        ["microsoft-edge", "microsoft-edge-stable", "msedge"],
    ),
    "chrome": (
        "Google Chrome",
        CHROMIUM,
        [r"Google\Chrome\Application\chrome.exe"],
        ["google-chrome", "google-chrome-stable", "chrome"],
    ),
    "brave": (
        "Brave",
        CHROMIUM,
        [r"BraveSoftware\Brave-Browser\Application\brave.exe"],
        ["brave-browser", "brave"],
    ),
    "chromium": (
        "Chromium",
        CHROMIUM,
        [r"Chromium\Application\chrome.exe"],
        ["chromium", "chromium-browser"],
    ),
    "vivaldi": (
        "Vivaldi",
        CHROMIUM,
        [r"Vivaldi\Application\vivaldi.exe"],
        ["vivaldi", "vivaldi-stable"],
    ),
    "opera": (
        "Opera",
        CHROMIUM,
        [r"Programs\Opera\opera.exe", r"Opera\opera.exe"],
        ["opera"],
    ),
    "firefox": (
        "Mozilla Firefox",
        GECKO,
        [r"Mozilla Firefox\firefox.exe"],
        ["firefox"],
    ),
}

# Chromium-family browsers are the ones the recorder/player can drive.
SUPPORTED_FAMILIES = {CHROMIUM}

_CACHE: tuple[float, list[BrowserInfo]] | None = None
_CACHE_TTL = 60.0


def _windows_roots() -> list[Path]:
    names = ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA", "ProgramW6432")
    roots = []
    for name in names:
        value = os.environ.get(name)
        if value:
            roots.append(Path(value))
    return roots


def _find_windows(relatives: list[str]) -> str:
    for root in _windows_roots():
        for relative in relatives:
            candidate = root / relative
            if candidate.exists():
                return str(candidate)
    return ""


def _find_posix(executables: list[str]) -> str:
    for executable in executables:
        found = shutil.which(executable)
        if found:
            return found
    # macOS application bundles
    if sys.platform == "darwin":
        bundles = {
            "microsoft-edge": "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "google-chrome": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "brave-browser": "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "chromium": "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "vivaldi": "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi",
            "opera": "/Applications/Opera.app/Contents/MacOS/Opera",
            "firefox": "/Applications/Firefox.app/Contents/MacOS/firefox",
        }
        for executable in executables:
            bundle = bundles.get(executable)
            if bundle and Path(bundle).exists():
                return bundle
    return ""


def _version(path: str) -> str:
    if not path:
        return ""
    try:
        if platform.system() == "Windows":
            completed = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    f"(Get-Item -LiteralPath '{path}').VersionInfo.ProductVersion",
                ],
                capture_output=True,
                text=True,
                timeout=8,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        else:
            completed = subprocess.run(
                [path, "--version"], capture_output=True, text=True, timeout=8
            )
        output = (completed.stdout or "").strip().splitlines()
        return output[0].strip() if output else ""
    except Exception:  # noqa: BLE001 - a missing version is not an error
        return ""


def detect(refresh: bool = False, with_version: bool = True) -> list[BrowserInfo]:
    """Return every known browser, installed ones first."""
    global _CACHE
    if not refresh and _CACHE and (time.time() - _CACHE[0]) < _CACHE_TTL:
        return _CACHE[1]

    is_windows = platform.system() == "Windows"
    results: list[BrowserInfo] = []
    for browser_id, (name, family, windows, posix) in CATALOG.items():
        path = _find_windows(windows) if is_windows else _find_posix(posix)
        info = BrowserInfo(
            id=browser_id,
            name=name,
            family=family,
            path=path,
            installed=bool(path),
            supported=family in SUPPORTED_FAMILIES,
        )
        if info.installed and with_version:
            info.version = _version(path)
        results.append(info)

    results.sort(key=lambda b: (not b.installed, not b.supported, b.name))
    _CACHE = (time.time(), results)
    return results


def installed(refresh: bool = False) -> list[BrowserInfo]:
    return [b for b in detect(refresh) if b.installed and b.supported]


def get(browser_id: str, refresh: bool = False) -> BrowserInfo | None:
    for browser in detect(refresh):
        if browser.id == browser_id:
            return browser
    return None


def resolve(preferred: str = "auto") -> BrowserInfo:
    """Pick the browser to drive.

    "auto" prefers Edge (it ships with Windows), then Chrome, then whatever
    Chromium-family browser is present.
    """
    available = installed()
    if not available:
        raise BrowserNotFound(
            "هېڅ ملاتړ شوی براوزر ونه موندل شو. "
            "مهرباني وکړئ Microsoft Edge یا Google Chrome نصب کړئ."
        )
    if preferred and preferred != "auto":
        for browser in available:
            if browser.id == preferred:
                return browser
        known = get(preferred)
        if known and not known.installed:
            raise BrowserNotFound(
                f"«{known.name}» پدې کمپیوټر کې نصب نه دی. "
                "له تنظیماتو بل براوزر وټاکئ."
            )
        raise BrowserNotFound(f"ناپېژندلی براوزر: {preferred}")

    for browser_id in ("edge", "chrome", "brave", "chromium", "vivaldi", "opera"):
        for browser in available:
            if browser.id == browser_id:
                return browser
    return available[0]


class BrowserNotFound(RuntimeError):
    pass
