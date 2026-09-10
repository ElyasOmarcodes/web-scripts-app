"""WebDriver factory for any installed Chromium-family browser.

Selenium 4.6+ ships Selenium Manager, which downloads the matching driver
(msedgedriver / chromedriver) automatically — the user installs nothing.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from selenium import webdriver
from selenium.webdriver.chrome.options import Options as ChromeOptions
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.edge.options import Options as EdgeOptions
from selenium.webdriver.edge.service import Service as EdgeService

from . import browsers, config
from .browsers import BrowserInfo, BrowserNotFound

COMMON_ARGS = [
    "--disable-notifications",
    "--disable-popup-blocking",
    "--disable-blink-features=AutomationControlled",
]

# Chrome tells every page it is being automated. Sites weigh that heavily when
# they decide to lock an account, so the give-aways are cleared before the
# first byte of the page runs.
STEALTH_JS = """
Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
if (!window.chrome) { window.chrome = {runtime: {}}; }
const query = navigator.permissions && navigator.permissions.query;
if (query) {
  navigator.permissions.query = (parameters) =>
    parameters && parameters.name === 'notifications'
      ? Promise.resolve({state: Notification.permission})
      : query.call(navigator.permissions, parameters);
}
"""


class BrowserError(RuntimeError):
    pass


def _extra_args() -> list[str]:
    """Extra command line switches, for containers and odd setups.

    WEBSCRIPTS_BROWSER_ARGS="--no-sandbox --disable-dev-shm-usage"
    """
    return [a for a in (os.environ.get("WEBSCRIPTS_BROWSER_ARGS") or "").split() if a]


def _profile_dir(browser: BrowserInfo):
    """Each browser gets its own profile so their logins never collide."""
    return config.PROFILE_DIR / browser.id


def screen_size() -> tuple[int, int]:
    """The desktop's size, used to tile several browser windows side by side."""
    override = os.environ.get("WEBSCRIPTS_SCREEN")
    if override and "x" in override:
        try:
            width, height = override.lower().split("x", 1)
            return int(width), int(height)
        except ValueError:
            pass
    if sys.platform == "win32":
        try:
            import ctypes

            user32 = ctypes.windll.user32
            user32.SetProcessDPIAware()
            return int(user32.GetSystemMetrics(0)), int(user32.GetSystemMetrics(1))
        except Exception:  # noqa: BLE001 - fall through to the default
            pass
    return 1920, 1080


def tile(index: int, count: int, screen: tuple[int, int] | None = None):
    """Where the index-th of `count` browser windows goes on screen.

    One window fills the screen; two split it left and right; three or four
    make a grid — so a task running on several accounts can be watched at a
    glance instead of one window hiding another.
    """
    width, height = screen or screen_size()
    count = max(1, min(count, 4))
    index = max(0, min(index, count - 1))
    if count == 1:
        return (0, 0), (width, height)
    if count == 2:
        cell = (width // 2, height)
        return (index * cell[0], 0), cell
    columns = 2
    rows = 2
    cell = (width // columns, height // rows)
    column = index % columns
    row = index // columns
    return (column * cell[0], row * cell[1]), cell


def build_options(
    browser: BrowserInfo,
    headless: bool = False,
    use_profile: bool = True,
    profile_path=None,
    window_size: tuple[int, int] | None = None,
    window_position: tuple[int, int] | None = None,
):
    options = EdgeOptions() if browser.id == "edge" else ChromeOptions()

    if browser.id not in {"edge", "chrome"} and browser.path:
        # Brave, Vivaldi, Opera and plain Chromium are driven through the
        # chromedriver, so the binary has to be pointed at explicitly.
        options.binary_location = browser.path

    if headless:
        options.add_argument("--headless=new")
        options.add_argument(
            "--window-size={},{}".format(*(window_size or (1440, 900)))
        )
    elif window_size:
        # A sized window: the sign-in flow, or one tile of a task running on
        # several accounts at once.
        options.add_argument("--window-size={},{}".format(*window_size))
    else:
        options.add_argument("--start-maximized")
    if window_position and not headless:
        options.add_argument("--window-position={},{}".format(*window_position))

    if use_profile:
        # An account brings its own profile directory so its session is
        # completely separate from every other account.
        profile = Path(profile_path) if profile_path else _profile_dir(browser)
        profile.mkdir(parents=True, exist_ok=True)
        options.add_argument(f"--user-data-dir={profile}")
        options.add_argument("--profile-directory=Default")

    for argument in COMMON_ARGS + _extra_args():
        options.add_argument(argument)
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    return options


def create_driver(
    headless: bool = False,
    use_profile: bool = True,
    browser: str | BrowserInfo = "auto",
    profile_path=None,
    window_size: tuple[int, int] | None = None,
    window_position: tuple[int, int] | None = None,
):
    """Start the requested browser and return the driver.

    Raises BrowserError with a message meant for the UI.
    """
    try:
        info = browser if isinstance(browser, BrowserInfo) else browsers.resolve(browser)
    except BrowserNotFound as exc:
        raise BrowserError(str(exc)) from exc

    options = build_options(
        info,
        headless=headless,
        use_profile=use_profile,
        profile_path=profile_path,
        window_size=window_size,
        window_position=window_position,
    )
    try:
        if info.id == "edge":
            driver = webdriver.Edge(service=EdgeService(), options=options)
        else:
            driver = webdriver.Chrome(service=ChromeService(), options=options)
    except Exception as exc:  # noqa: BLE001 - surfaced to the UI as text
        raise BrowserError(_explain(info, exc)) from exc

    _harden(driver)
    driver.set_page_load_timeout(60)
    driver.set_script_timeout(30)
    return driver


def _harden(driver) -> None:
    """Hide the automation flags from every document the browser opens."""
    try:
        driver.execute_cdp_cmd(
            "Page.addScriptToEvaluateOnNewDocument", {"source": STEALTH_JS}
        )
    except Exception:  # noqa: BLE001 - a browser without CDP still works
        pass


def _explain(browser: BrowserInfo, exc: Exception) -> str:
    message = str(exc)
    lowered = message.lower()
    if "user data directory is already in use" in lowered:
        return (
            f"د {browser.name} پروفایل بل ځای کې پرانیستل شوی دی. "
            f"د WebScripts ټولې {browser.name} کړکۍ وتړئ او بیا هڅه وکړئ."
        )
    if "cannot find" in lowered or "no such file" in lowered:
        return f"{browser.name} ونه موندل شو ({browser.path or 'بې لارې'})."
    if "session not created" in lowered and "version" in lowered:
        return (
            f"د {browser.name} او د هغه د ډرایور نسخې سره نه خوري. "
            "براوزر تازه کړئ او بیا هڅه وکړئ."
        )
    return f"د براوزر پیلولو تېروتنه ({browser.name}): {message.splitlines()[0]}"
