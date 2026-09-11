"""Is this proxy alive, how fast is it, and where does it come out?

One request through the proxy answers all three: a public "what is my IP"
service returns the address the site would see, together with its country and
city. That is the number that matters — not the proxy's own address, but the
one the account will appear from.

Nothing here is guessed: a proxy that cannot be reached is *dead*, and a check
that could not run at all (no internet on this machine) leaves the proxy as it
was, with a note.
"""

from __future__ import annotations

import json
import socket
import time
import urllib.error
import urllib.request
from typing import Any

from .proxies import ALIVE, DEAD, UNKNOWN, Proxy

# Free, no key, returns the exit address with its country and city. Tried in
# order; the first one that answers wins.
LOOKUPS = [
    ("http://ip-api.com/json/?fields=query,country,city,status", "ip-api"),
    ("https://ipinfo.io/json", "ipinfo"),
]

TIMEOUT = 12.0


def _read_through(proxy: Proxy, url: str, timeout: float) -> dict[str, Any]:
    handler = urllib.request.ProxyHandler({
        "http": proxy.url(),
        "https": proxy.url(),
    })
    opener = urllib.request.build_opener(handler)
    opener.addheaders = [("User-Agent", "WebScripts/1.0")]
    with opener.open(url, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def check(proxy: Proxy, timeout: float = TIMEOUT) -> dict[str, Any]:
    """Try the proxy. Returns what the store needs to record."""
    if proxy.scheme.startswith("socks"):
        # urllib speaks HTTP proxies only. A SOCKS proxy still works in the
        # browser; it just cannot be measured from here.
        return {
            "status": UNKNOWN,
            "note": "SOCKS پروکسي له دې ځایه نه شي کتل کېدای — په براوزر کې کار کوي",
        }

    last_error = ""
    for url, _name in LOOKUPS:
        started = time.perf_counter()
        try:
            body = _read_through(proxy, url, timeout)
        except urllib.error.HTTPError as exc:
            # The proxy answered — with a refusal. 407 means the credentials
            # are wrong, which is the proxy's problem, not the network's.
            if exc.code == 407:
                return {"status": DEAD, "note": "کارن‌نوم/پټنوم ونه منل شو (407)"}
            last_error = f"HTTP {exc.code}"
            continue
        except (urllib.error.URLError, socket.timeout, OSError) as exc:
            last_error = _short(exc)
            continue
        except Exception as exc:  # noqa: BLE001
            last_error = _short(exc)
            continue

        latency = int((time.perf_counter() - started) * 1000)
        exit_ip = str(body.get("query") or body.get("ip") or "")
        country = str(body.get("country") or body.get("country_name") or "")
        city = str(body.get("city") or "")
        if body.get("status") == "fail" or not exit_ip:
            last_error = "د IP ځواب ناسم و"
            continue
        return {
            "status": ALIVE,
            "latency_ms": latency,
            "exit_ip": exit_ip,
            "country": country,
            "city": city,
            "note": "",
        }

    return {"status": DEAD, "note": last_error or "ځواب یې ور نه کړ"}


def _short(exc: Exception) -> str:
    text = str(exc)
    if "timed out" in text.lower():
        return "وخت یې پوره شو"
    if "Connection refused" in text:
        return "اړیکه رد شوه"
    if "Name or service not known" in text or "getaddrinfo" in text:
        return "پته ونه پېژندل شوه"
    return text.split("\n", 1)[0][:110]
