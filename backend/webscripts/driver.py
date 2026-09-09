"""Microsoft Edge WebDriver factory.

Selenium 4.6+ ships Selenium Manager, which downloads a matching
`msedgedriver` automatically - the user does not have to install anything
besides Edge itself.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from selenium import webdriver
from selenium.webdriver.edge.options import Options as EdgeOptions
from selenium.webdriver.edge.service import Service as EdgeService

from . import config


class BrowserError(RuntimeError):
    pass


def build_options(headless: bool = False, use_profile: bool = True) -> EdgeOptions:
    options = EdgeOptions()
    if headless:
        options.add_argument("--headless=new")
        options.add_argument("--window-size=1440,900")
    else:
        options.add_argument("--start-maximized")

    if use_profile:
        config.PROFILE_DIR.mkdir(parents=True, exist_ok=True)
        options.add_argument(f"--user-data-dir={config.PROFILE_DIR}")
        options.add_argument("--profile-directory=Default")

    options.add_argument("--disable-notifications")
    options.add_argument("--disable-popup-blocking")
    # Hide the "Edge is being controlled by automated software" bar and the
    # automation flag most sites sniff for.
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    options.add_argument("--disable-blink-features=AutomationControlled")
    return options


def create_driver(headless: bool = False, use_profile: bool = True):
    """Start Edge and return the driver.

    Raises BrowserError with an actionable message when Edge is missing or the
    profile is already locked by another Edge window.
    """
    options = build_options(headless=headless, use_profile=use_profile)
    try:
        driver = webdriver.Edge(service=EdgeService(), options=options)
    except Exception as exc:  # noqa: BLE001 - surfaced to the UI as text
        message = str(exc)
        if "user data directory is already in use" in message.lower():
            raise BrowserError(
                "د Edge پروفایل بل ځای کې پرانیستل شوی دی. "
                "مهرباني وکړئ د WebScripts ټول Edge کړکۍ وتړئ او بیا هڅه وکړئ."
            ) from exc
        if not _edge_installed():
            raise BrowserError(
                "Microsoft Edge ونه موندل شو. مهرباني وکړئ Edge نصب کړئ."
            ) from exc
        raise BrowserError(f"د براوزر پیلولو تېروتنه: {message}") from exc

    driver.set_page_load_timeout(60)
    driver.set_script_timeout(30)
    return driver


def _edge_installed() -> bool:
    if shutil.which("msedge"):
        return True
    candidates = [
        Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
        Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
        Path("/usr/bin/microsoft-edge"),
        Path("/usr/bin/microsoft-edge-stable"),
    ]
    return any(path.exists() for path in candidates)
