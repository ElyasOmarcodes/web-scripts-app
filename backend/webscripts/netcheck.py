"""Why the page did not load — said in words, not in ``ERR_`` codes.

When a script runs and the browser shows "no internet" while the same link
opens perfectly in the user's own browser, the cause is almost never the
internet. It is nearly always the proxy: the account has one assigned, and the
proxy is dead, or asleep, or refusing the username and password, or — the most
common of all — it only lets in addresses the seller has on a whitelist, and
this machine's address is not one of them. Chrome answers all of those with
the same grey page, so the app has to look at the error code and say which it
was.

Everything here is read-only: it looks at the page the browser ended up on and
turns it into one sentence the user can act on.
"""

from __future__ import annotations

import sys

# Chrome's code → what actually happened, and what to do about it.
MEANINGS: dict[str, str] = {
    "ERR_PROXY_CONNECTION_FAILED": (
        "پروکسي ته اړیکه ونه نیول شوه. ښایي پروکسي مړه وي، یا ستاسو د "
        "کمپیوټر IP د پروکسي په اجازه‌لیست (whitelist) کې نه وي."
    ),
    "ERR_TUNNEL_CONNECTION_FAILED": (
        "پروکسي اړیکه پرې کړه. ډېر ځله پدې معنا چې کارن‌نوم/پټنوم یې ونه "
        "منل شو، یا ستاسو IP د پروکسي په اجازه‌لیست کې نشته."
    ),
    "ERR_PROXY_AUTH_UNSUPPORTED": "پروکسي د کارن‌نوم/پټنوم بڼه ونه منله.",
    "ERR_PROXY_AUTH_REQUESTED": "پروکسي کارن‌نوم او پټنوم غوښتل — نا‌سم دي.",
    "ERR_NO_SUPPORTED_PROXIES": "د پروکسي ډول (scheme) براوزر نه پېژني.",
    "ERR_SOCKS_CONNECTION_FAILED": "SOCKS پروکسي ځواب ور نه کړ.",
    "ERR_INTERNET_DISCONNECTED": "کمپیوټر انټرنیټ نه لري.",
    "ERR_NAME_NOT_RESOLVED": (
        "د سایټ پته ونه پېژندل شوه (DNS). که پروکسي فعاله وي، ښایي پروکسي "
        "پخپله پته نه شي حل کولای."
    ),
    "ERR_CONNECTION_TIMED_OUT": "وخت پوره شو — ځواب رانه غی.",
    "ERR_CONNECTION_REFUSED": "اړیکه رد شوه.",
    "ERR_CONNECTION_RESET": "اړیکه په منځ کې پرې شوه.",
    "ERR_CONNECTION_CLOSED": "اړیکه وتړل شوه.",
    "ERR_EMPTY_RESPONSE": "سرور تش ځواب راولېږه.",
    "ERR_TIMED_OUT": "وخت پوره شو.",
    "ERR_SSL_PROTOCOL_ERROR": "د خوندیتوب (SSL) تېروتنه — ښایي پروکسي ټرافیک بدلوي.",
    "ERR_CERT_AUTHORITY_INVALID": "د سایټ سند د باور وړ نه و — ښایي پروکسي مینځ کې وي.",
    "ERR_ADDRESS_UNREACHABLE": "پته ته لار نشته.",
}

# Codes that can only come from a proxy.
PROXY_CODES = {
    "ERR_PROXY_CONNECTION_FAILED",
    "ERR_TUNNEL_CONNECTION_FAILED",
    "ERR_PROXY_AUTH_UNSUPPORTED",
    "ERR_PROXY_AUTH_REQUESTED",
    "ERR_NO_SUPPORTED_PROXIES",
    "ERR_SOCKS_CONNECTION_FAILED",
}

# Codes that are innocent on their own, but when a proxy is in the way it is
# the first thing to suspect — a dead proxy times out exactly like a dead site.
SUSPECT_CODES = {
    "ERR_TIMED_OUT",
    "ERR_CONNECTION_TIMED_OUT",
    "ERR_EMPTY_RESPONSE",
    "ERR_CONNECTION_RESET",
    "ERR_CONNECTION_CLOSED",
    "ERR_NAME_NOT_RESOLVED",
    "ERR_FAILED",
}

_READ_ERROR = """
try {
  if (!document || !document.body) return '';
  var code = document.querySelector('.error-code, #error-code');
  if (code && code.textContent) return code.textContent.trim();
  var body = document.body.innerText || '';
  var found = body.match(/ERR_[A-Z0-9_]+/);
  return found ? found[0] : '';
} catch (e) { return ''; }
"""


def code_from(text: str) -> str:
    """Pull an ERR_ code out of any message."""
    if not text:
        return ""
    marker = text.find("ERR_")
    if marker < 0:
        return ""
    code = ""
    for character in text[marker:]:
        if character.isalnum() or character == "_":
            code += character
        else:
            break
    return code


def read(driver) -> str:
    """The error code of the page the browser is on now, or ""."""
    try:
        url = driver.current_url or ""
    except Exception:  # noqa: BLE001
        url = ""
    try:
        found = driver.execute_script("return (function(){" + _READ_ERROR + "})();")
    except Exception:  # noqa: BLE001 - no page, no error to read
        found = ""
    code = code_from(str(found or ""))
    if not code and url.startswith("chrome-error://"):
        return "ERR_FAILED"
    return code


def explain(code: str, proxy=None, url: str = "") -> str:
    """One sentence: what went wrong, and where to look."""
    if not code:
        return ""
    meaning = MEANINGS.get(code, f"براوزر پاڼه ونه لوستله ({code}).")
    parts = [f"پاڼه ونه پرانیستل شوه: {meaning}"]

    if proxy is not None and code in (PROXY_CODES | SUSPECT_CODES):
        parts.append(f"کارېدلې پروکسي: {proxy.title()}.")
        parts.append(
            "د «پروکسي» پاڼې څخه یې چک کړئ؛ که مړه وه، اکاونټ ته بله پروکسي "
            "وټاکئ یا د اکاونټ لپاره پروکسي بندول غوره کړئ."
        )
    elif proxy is not None:
        parts.append(f"(پروکسي: {proxy.title()})")
    elif code in PROXY_CODES:
        # No proxy of ours — so something else on the machine is putting one
        # in the way. This is the usual answer when the same link opens fine
        # in the user's own browser.
        parts.append(
            "پدې اکاونټ کې پروکسي نه ده ټاکل شوې، خو براوزر بیا هم د پروکسي "
            "شکایت کوي — نو د ویندوز په کچه یوه پروکسي/VPN یا د انټي‌ویروس "
            "«ویب شیلډ» په منځ کې ده. له تنظیماتو یې بند کړئ او بیا هڅه وکړئ."
        )
    if url:
        parts.append(f"لینک: {url}")
    return " ".join(parts)


def system_proxy() -> str:
    """A proxy the whole machine is set to use, or "".

    Chrome inherits it whether we ask or not, so when WebScripts has no proxy
    of its own and pages still fail, this is usually the answer.
    """
    import os

    for name in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy",
                 "ALL_PROXY", "all_proxy"):
        value = os.environ.get(name)
        if value:
            return value
    if sys.platform == "win32":
        try:
            import winreg

            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\\Microsoft\\Windows\\CurrentVersion\\"
                r"Internet Settings",
            )
            enabled, _ = winreg.QueryValueEx(key, "ProxyEnable")
            if enabled:
                server, _ = winreg.QueryValueEx(key, "ProxyServer")
                return str(server)
        except Exception:  # noqa: BLE001 - no key, no proxy
            return ""
    return ""


def trouble(driver, proxy=None, url: str = "") -> str:
    """Read the page and explain it, or "" when the page is fine."""
    return explain(read(driver), proxy=proxy, url=url)


def from_exception(exc: Exception, proxy=None, url: str = "") -> str:
    """Same, for the errors Selenium raises instead of showing a page."""
    return explain(code_from(str(exc)), proxy=proxy, url=url)
