"""Proxies: one address per account, so accounts do not share an IP.

Three accounts on the same site, all coming from one address, look like one
person with three accounts — which is exactly what the site is watching for.
Giving each account its own proxy is the single biggest thing that keeps them
apart.

A proxy line is stored with its credentials, so this file is written with
owner-only permissions, like the cookie files next to it.
"""

from __future__ import annotations

import json
import os
import random
import re
import stat
import tempfile
import time
from pathlib import Path
from typing import Any, Iterable

from pydantic import BaseModel, Field

from . import config
from .models import new_id

# Whether the proxy answered when it was last tried.
ALIVE = "alive"
DEAD = "dead"
CHECKING = "checking"
UNKNOWN = "unknown"

SCHEMES = {"http", "https", "socks5", "socks4"}

# host:port:user:pass — the shape Webshare and most sellers hand out.
_HOST = r"[A-Za-z0-9_.\-]+"


class Proxy(BaseModel):
    id: str = Field(default_factory=lambda: new_id("prx"))
    label: str = ""
    scheme: str = "http"
    host: str = ""
    port: int = 0
    username: str = ""
    password: str = ""
    enabled: bool = True

    # What the last check found.
    status: str = UNKNOWN
    latency_ms: int | None = None
    exit_ip: str = ""
    country: str = ""
    city: str = ""
    note: str = ""
    checked_at: int | None = None
    last_used_at: int | None = None
    created_at: int = Field(default_factory=lambda: int(time.time() * 1000))

    @property
    def address(self) -> str:
        return f"{self.host}:{self.port}"

    @property
    def needs_auth(self) -> bool:
        return bool(self.username or self.password)

    def url(self, with_auth: bool = True) -> str:
        """proxy URL, as urllib and Chrome want it."""
        if with_auth and self.needs_auth:
            return f"{self.scheme}://{self.username}:{self.password}@{self.address}"
        return f"{self.scheme}://{self.address}"

    def title(self) -> str:
        return self.label or self.address

    def summary(self, used_by: int = 0) -> dict[str, Any]:
        return {
            **self.model_dump(exclude={"password"}),
            # The password is never sent to the UI; it only leaves this file
            # when a browser or a check actually needs it.
            "has_password": bool(self.password),
            "address": self.address,
            "used_by": used_by,
        }


def parse_line(line: str) -> Proxy | None:
    """Read one proxy out of whatever shape the seller wrote it in.

    Understood:
        host:port
        host:port:user:pass          ← Webshare and most lists
        user:pass@host:port
        scheme://user:pass@host:port
        scheme://host:port
    """
    text = line.strip()
    if not text or text.startswith("#"):
        return None
    text = text.replace(",", " ").split()[0] if " " in text else text

    scheme = "http"
    if "://" in text:
        scheme, _, text = text.partition("://")
        scheme = scheme.lower()
        if scheme not in SCHEMES:
            return None

    username = password = ""
    if "@" in text:
        credentials, _, text = text.rpartition("@")
        username, _, password = credentials.partition(":")

    parts = text.split(":")
    if len(parts) == 4 and not username:
        # host:port:user:pass
        host, port, username, password = parts
    elif len(parts) == 2:
        host, port = parts
    else:
        return None

    if not re.fullmatch(_HOST, host) or not port.isdigit():
        return None
    number = int(port)
    if not 1 <= number <= 65535:
        return None

    return Proxy(
        scheme=scheme,
        host=host,
        port=number,
        username=username,
        password=password,
    )


def parse_many(text: str) -> tuple[list[Proxy], list[str]]:
    """Parse a pasted list; returns (proxies, lines that made no sense)."""
    found: list[Proxy] = []
    bad: list[str] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        proxy = parse_line(line)
        if proxy is None:
            bad.append(line.strip()[:80])
        else:
            found.append(proxy)
    return found, bad


class ProxyStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else config.BASE_DIR / "proxies.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._proxies: list[Proxy] | None = None

    # ----------------------------------------------------------- storage

    def _load(self) -> list[Proxy]:
        if self._proxies is not None:
            return self._proxies
        proxies: list[Proxy] = []
        if self.path.exists():
            try:
                raw = json.loads(self.path.read_text("utf-8"))
                for item in raw.get("proxies", []):
                    try:
                        proxies.append(Proxy.model_validate(item))
                    except Exception:  # noqa: BLE001 - skip one broken row
                        continue
            except Exception:  # noqa: BLE001 - a corrupt file starts empty
                proxies = []
        self._proxies = proxies
        return proxies

    def _save(self) -> None:
        data = {"proxies": [p.model_dump() for p in self._load()]}
        text = json.dumps(data, ensure_ascii=False, indent=2)
        fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
            # Proxy credentials are as private as the cookies next to them.
            os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
            os.replace(tmp, self.path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # -------------------------------------------------------------- crud

    def list(self) -> list[Proxy]:
        return list(self._load())

    def get(self, proxy_id: str) -> Proxy | None:
        for proxy in self._load():
            if proxy.id == proxy_id:
                return proxy
        return None

    def find(self, host: str, port: int) -> Proxy | None:
        for proxy in self._load():
            if proxy.host == host and proxy.port == port:
                return proxy
        return None

    def add_many(self, proxies: Iterable[Proxy]) -> tuple[list[Proxy], int]:
        """Add proxies, skipping ones already stored. Returns (added, skipped)."""
        added: list[Proxy] = []
        skipped = 0
        rows = self._load()
        for proxy in proxies:
            if self.find(proxy.host, proxy.port) is not None:
                skipped += 1
                continue
            rows.append(proxy)
            added.append(proxy)
        if added:
            self._save()
        return added, skipped

    def update(self, proxy_id: str, **changes: Any) -> Proxy | None:
        proxy = self.get(proxy_id)
        if proxy is None:
            return None
        for field, value in changes.items():
            if value is not None and hasattr(proxy, field):
                setattr(proxy, field, value)
        self._save()
        return proxy

    def set_status(
        self,
        proxy_id: str,
        status: str,
        *,
        latency_ms: int | None = None,
        exit_ip: str = "",
        country: str = "",
        city: str = "",
        note: str = "",
    ) -> Proxy | None:
        proxy = self.get(proxy_id)
        if proxy is None:
            return None
        proxy.status = status
        proxy.note = note
        if status != CHECKING:
            proxy.checked_at = int(time.time() * 1000)
            proxy.latency_ms = latency_ms
            if exit_ip:
                proxy.exit_ip = exit_ip
            if country:
                proxy.country = country
            if city:
                proxy.city = city
        self._save()
        return proxy

    def mark_used(self, proxy_id: str) -> None:
        proxy = self.get(proxy_id)
        if proxy is None:
            return
        proxy.last_used_at = int(time.time() * 1000)
        self._save()

    def delete(self, proxy_id: str) -> bool:
        rows = self._load()
        remaining = [p for p in rows if p.id != proxy_id]
        if len(remaining) == len(rows):
            return False
        self._proxies = remaining
        self._save()
        return True

    # ------------------------------------------------------- assignment

    def usable(self) -> list[Proxy]:
        """Proxies a run may pick: enabled, and not known to be dead."""
        return [p for p in self._load() if p.enabled and p.status != DEAD]

    def random_usable(self, rng: random.Random | None = None) -> Proxy | None:
        options = self.usable()
        if not options:
            return None
        return (rng or random).choice(options)

    def overview(self, assignments: dict[str, str] | None = None) -> dict:
        rows = self._load()
        used = set((assignments or {}).values())
        return {
            "total": len(rows),
            "alive": sum(1 for p in rows if p.status == ALIVE),
            "dead": sum(1 for p in rows if p.status == DEAD),
            "unknown": sum(1 for p in rows if p.status not in {ALIVE, DEAD}),
            "assigned": sum(1 for p in rows if p.id in used),
            "free": sum(1 for p in rows if p.id not in used and p.enabled),
        }


def distribute(
    proxies: list[Proxy], account_ids: list[str], rng: random.Random | None = None
) -> dict[str, str]:
    """Hand each account its own proxy, shuffled.

    One account keeps one address: an account whose IP changes every run looks
    stranger to a site than one that never moves. When there are fewer proxies
    than accounts the list wraps around, and the caller is told.
    """
    if not proxies or not account_ids:
        return {}
    pool = list(proxies)
    (rng or random).shuffle(pool)
    return {
        account_id: pool[index % len(pool)].id
        for index, account_id in enumerate(account_ids)
    }
