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

from . import browsers, config, disguise, proxy_ext
from .browsers import BrowserInfo, BrowserNotFound
from .fingerprints import Fingerprint
from .proxies import Proxy

COMMON_ARGS = [
    "--disable-notifications",
    "--disable-popup-blocking",
    "--disable-blink-features=AutomationControlled",
    # WebRTC opens its own UDP path, which does not go through the proxy — so
    # a page could read the machine's real address while everything else is
    # proxied. This tells the browser not to take that path at all.
    "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
    # Never ask, and never answer, where the machine is: the answer would be
    # the real city, not the proxy's.
    "--deny-permission-prompts",
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
    proxy: Proxy | None = None,
    fingerprint: Fingerprint | None = None,
    country: str = "",
):
    options = EdgeOptions() if browser.id == "edge" else ChromeOptions()
    extension_dir = None
    if window_size is None and fingerprint is not None:
        # An account's window keeps one size for life. A maximised window
        # reports the real monitor, which is the same on every account and
        # would undo the screen the identity claims — and a window that
        # changes size every run is itself something to notice.
        window_size = fingerprint.window

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

    if proxy is not None:
        if proxy.needs_auth:
            # Chrome throws away credentials given on the command line; a tiny
            # extension sets the proxy and answers its login prompt instead.
            extension_dir = proxy_ext.build(proxy)
            options.add_argument(f"--load-extension={extension_dir}")
            # An extension cannot load in the old headless mode.
            options.add_argument("--disable-extensions-except=" + str(extension_dir))
        else:
            options.add_argument(f"--proxy-server={proxy.url(with_auth=False)}")

    if fingerprint is not None:
        # Set on the command line as well as over CDP: this one is in place
        # before the first request leaves, including the one that fetches the
        # very first page.
        options.add_argument(f"--user-agent={fingerprint.ua}")
        languages = disguise.languages_for(fingerprint, country)
        if languages:
            options.add_argument("--lang=" + languages[0])
            options.add_argument(
                "--accept-lang=" + ",".join(languages)
            )

    for argument in COMMON_ARGS + _extra_args():
        options.add_argument(argument)
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    # Keep the page's own errors, so "the button does nothing" can be
    # answered with what the site actually complained about instead of a
    # guess. Costs nothing when nothing goes wrong.
    options.set_capability("goog:loggingPrefs", {"browser": "ALL"})
    # The caller must remove the directory when the browser closes.
    options.webscripts_extension_dir = extension_dir  # type: ignore[attr-defined]
    return options


def create_driver(
    headless: bool = False,
    use_profile: bool = True,
    browser: str | BrowserInfo = "auto",
    profile_path=None,
    window_size: tuple[int, int] | None = None,
    window_position: tuple[int, int] | None = None,
    proxy: Proxy | None = None,
    fingerprint: Fingerprint | None = None,
    seed: int = 0,
    country: str = "",
    city: str = "",
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
        proxy=proxy,
        fingerprint=fingerprint,
        country=country,
    )
    extension_dir = getattr(options, "webscripts_extension_dir", None)
    try:
        if info.id == "edge":
            driver = webdriver.Edge(service=EdgeService(), options=options)
        else:
            driver = webdriver.Chrome(service=ChromeService(), options=options)
    except Exception as exc:  # noqa: BLE001 - surfaced to the UI as text
        proxy_ext.clean(extension_dir)
        raise BrowserError(_explain(info, exc)) from exc

    # Remembered on the driver so quitting can clean the password off disk.
    driver.webscripts_extension_dir = extension_dir
    _harden(driver)
    if fingerprint is not None:
        driver.webscripts_identity = disguise.apply(
            driver, fingerprint, seed, country=country, city=city
        )
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


# Noise every site produces and nobody needs to read.
_BORING = (
    "favicon",
    "net::ERR_BLOCKED_BY_CLIENT",
    "Failed to load resource: the server responded with a status of 4",
    "Tracking Prevention",
    "third-party cookie",
)


def console_errors(driver, limit: int = 6) -> list[str]:
    """What the page itself complained about, worst first.

    A button that does nothing has almost always thrown something first.
    """
    try:
        entries = driver.get_log("browser")
    except Exception:  # noqa: BLE001 - not every driver keeps a log
        return []
    found = []
    for entry in entries:
        if entry.get("level") not in {"SEVERE", "ERROR"}:
            continue
        message = str(entry.get("message", "")).strip()
        if not message or any(bit in message for bit in _BORING):
            continue
        # Chrome prefixes the source file and line; the tail is the message.
        found.append(message.split(" ", 2)[-1][:300])
    # Newest last is how a log reads; keep the last few.
    return found[-limit:]


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
