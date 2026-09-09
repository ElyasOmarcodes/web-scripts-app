"""WebDriver factory for any installed Chromium-family browser.

Selenium 4.6+ ships Selenium Manager, which downloads the matching driver
(msedgedriver / chromedriver) automatically — the user installs nothing.
"""

from __future__ import annotations

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


class BrowserError(RuntimeError):
    pass


def _profile_dir(browser: BrowserInfo):
    """Each browser gets its own profile so their logins never collide."""
    return config.PROFILE_DIR / browser.id


def build_options(
    browser: BrowserInfo,
    headless: bool = False,
    use_profile: bool = True,
    profile_path=None,
    window_size: tuple[int, int] | None = None,
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
        # A small window, used for the "sign in to this account" flow.
        options.add_argument("--window-size={},{}".format(*window_size))
    else:
        options.add_argument("--start-maximized")

    if use_profile:
        # An account brings its own profile directory so its session is
        # completely separate from every other account.
        profile = Path(profile_path) if profile_path else _profile_dir(browser)
        profile.mkdir(parents=True, exist_ok=True)
        options.add_argument(f"--user-data-dir={profile}")
        options.add_argument("--profile-directory=Default")

    for argument in COMMON_ARGS:
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
    )
    try:
        if info.id == "edge":
            driver = webdriver.Edge(service=EdgeService(), options=options)
        else:
            driver = webdriver.Chrome(service=ChromeService(), options=options)
    except Exception as exc:  # noqa: BLE001 - surfaced to the UI as text
        raise BrowserError(_explain(info, exc)) from exc

    driver.set_page_load_timeout(60)
    driver.set_script_timeout(30)
    return driver


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
