"""Signing an account in, and reusing that session later.

The user signs in by hand in a small browser window — WebScripts never sees or
stores the password. Once the site hands out its session cookies, they are
exported next to the account's own browser profile.
"""

from __future__ import annotations

import time
from typing import Callable

from selenium.common.exceptions import WebDriverException

from .accounts import (
    ALIVE,
    DEAD,
    UNKNOWN,
    Account,
    AccountStore,
    Category,
    belongs_to,
    has_session,
)

# A small window, off to the side of the user's work.
LOGIN_WINDOW = (560, 780)

# Cookie fields Selenium accepts on add_cookie(); everything else is dropped.
COOKIE_FIELDS = {"name", "value", "domain", "path", "secure", "httpOnly", "expiry", "sameSite"}


def capture_cookies(driver, category: Category) -> list[dict]:
    """Every cookie of this site that the browser currently holds."""
    try:
        cookies = driver.get_cookies()
    except WebDriverException:
        return []
    return [c for c in cookies if isinstance(c, dict) and belongs_to(c, category)]


def signed_in(driver, category: Category) -> bool:
    return has_session(capture_cookies(driver, category), category)


def read_display_name(driver) -> str:
    """A best-effort label for the account, taken from the page itself."""
    try:
        title = (driver.title or "").strip()
    except WebDriverException:
        return ""
    # "(3) Facebook" / "Home / X" -> keep it short and free of noise.
    for junk in ("(", ")"):
        title = title.replace(junk, " ")
    title = " ".join(title.split())
    return title[:48]


def wait_for_login(
    driver,
    category: Category,
    should_stop: Callable[[], bool],
    on_log: Callable[[str, str], None] | None = None,
    poll: float = 1.0,
    settle: float = 2.5,
) -> list[dict]:
    """Poll until the site hands out a session cookie, then return the cookies.

    Returns an empty list when the user cancelled or closed the window first.
    """
    log = on_log or (lambda level, message: None)
    announced = False

    while not should_stop():
        try:
            if signed_in(driver, category):
                # Give the site a moment to finish writing the rest.
                log("info", "ننوتل وپېژندل شول — کوکیز اخیستل کېږي…")
                time.sleep(settle)
                return capture_cookies(driver, category)
            if not announced:
                announced = True
                log("info", "د ننوتلو انتظار… په براوزر کې خپل حساب ته ننوځئ.")
        except WebDriverException:
            # Window closed by hand.
            return []
        time.sleep(poll)
    # Stopped by the user: take whatever the browser has, it may be enough.
    return capture_cookies(driver, category)


def apply_cookies(driver, store: AccountStore, account: Account, category: Category,
                  on_log: Callable[[str, str], None] | None = None) -> int:
    """Seed a browser with the account's saved cookies.

    Cookies can only be set while the browser is on the matching domain, so the
    domains are visited once each before the script's own first step.
    """
    log = on_log or (lambda level, message: None)
    cookies = store.load_cookies(account.id)
    if not cookies:
        return 0

    by_domain: dict[str, list[dict]] = {}
    for cookie in cookies:
        domain = str(cookie.get("domain") or "").lstrip(".")
        if domain:
            by_domain.setdefault(domain, []).append(cookie)

    applied = 0
    for domain, items in by_domain.items():
        try:
            driver.get(f"https://{domain}/")
        except WebDriverException:
            continue
        for cookie in items:
            if _add_cookie(driver, cookie):
                applied += 1
        # Sites read their session on load, so the seeded page is reloaded to
        # come back as the signed-in user.
        try:
            driver.get(f"https://{domain}/")
        except WebDriverException:
            pass

    if applied:
        store.mark_used(account.id)
        log("info", f"د «{account.label}» {applied} کوکیز پلي شول.")
    return applied


def _add_cookie(driver, cookie: dict) -> bool:
    """Restore one cookie, keeping its domain whenever the browser allows it.

    Dropping the domain turns ".facebook.com" into a host-only cookie for
    "facebook.com", which "www.facebook.com" never receives — the account then
    looks signed out again. So the original domain is tried first, and only
    dropped when the browser refuses it.
    """
    clean = {k: v for k, v in cookie.items() if k in COOKIE_FIELDS}
    expiry = clean.get("expiry")
    if isinstance(expiry, (float, str)):
        try:
            clean["expiry"] = int(float(expiry))
        except (TypeError, ValueError):
            clean.pop("expiry", None)
    if clean.get("sameSite") == "None" and not clean.get("secure"):
        # Chrome drops SameSite=None cookies that are not secure.
        clean["secure"] = True
    try:
        driver.add_cookie(clean)
        return True
    except WebDriverException:
        pass
    clean.pop("domain", None)
    clean.pop("sameSite", None)
    try:
        driver.add_cookie(clean)
        return True
    except WebDriverException:
        return False


# ---------------------------------------------------------------- liveness


def cookies_expired(cookies: list[dict], category: Category, now: float | None = None) -> bool:
    """Are the session cookies past their expiry date?

    This is the cheap half of the check: an expired cookie is dead without
    asking the site. A cookie with no expiry is a session cookie — it lives as
    long as the browser profile does, so this says nothing about it.
    """
    now = now if now is not None else time.time()
    wanted = set(category.session_cookies)
    if not wanted:
        return False
    seen = False
    for cookie in cookies:
        if cookie.get("name") not in wanted:
            continue
        seen = True
        expiry = cookie.get("expiry")
        if expiry is None:
            return False  # a session cookie: cannot be judged from here
        try:
            if float(expiry) > now:
                return False
        except (TypeError, ValueError):
            return False
    # Every session cookie we hold has a date, and every date has passed.
    return seen


def check_cookies(
    store: AccountStore,
    account: Account,
    category: Category,
    driver_factory,
    on_log: Callable[[str, str], None] | None = None,
) -> tuple[str, str]:
    """Do this account's cookies still open the site?

    Returns (state, note). The site is asked for real — cookies are loaded
    into a throwaway headless browser, the site's own page is opened, and the
    answer is whether it still hands out a session. Anything that stops the
    check from happening (no internet, no browser) is "unknown", never "dead":
    a wrong red light would send the user re-logging in for nothing.
    """
    log = on_log or (lambda level, message: None)
    cookies = store.load_cookies(account.id)
    if not cookies:
        return DEAD, "هېڅ کوکي نشته"
    if cookies_expired(cookies, category):
        return DEAD, "د کوکیزو نېټه تېره ده"

    driver = None
    try:
        driver = driver_factory()
        applied = apply_cookies(driver, store, account, category, log)
        if not applied:
            return UNKNOWN, "کوکیز پلي نه شول"
        if signed_in(driver, category):
            name = read_display_name(driver)
            return ALIVE, name
        return DEAD, "سایټ ناسته ونه پېژندله"
    except Exception as exc:  # noqa: BLE001 - a failed check is not a dead account
        return UNKNOWN, str(exc).splitlines()[0][:120]
    finally:
        if driver is not None:
            try:
                driver.quit()
            except Exception:  # noqa: BLE001
                pass
