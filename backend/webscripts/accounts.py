"""Saved website accounts: log in once, reuse the session forever.

Two things are kept per account:

* a **dedicated browser profile directory** — this is what actually keeps the
  session alive, exactly as if the user had a separate browser for it;
* an **exported cookie file** — a portable copy used to seed a fresh profile
  and to tell whether the session is still valid.

Cookies are session tokens: whoever holds them is logged in. They are stored
under the user's own app directory with owner-only permissions and never leave
the machine.
"""

from __future__ import annotations

import json
import os
import stat
import tempfile
import time
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from . import config
from .models import new_id


class Category(BaseModel):
    """A website we can hold accounts for."""

    id: str
    name: str
    login_url: str
    # Cookies from these domains belong to the account.
    domains: list[str] = Field(default_factory=list)
    # Presence of any of these cookie names means the login finished.
    session_cookies: list[str] = Field(default_factory=list)
    max_accounts: int = 2
    color: str = "blue"
    enabled: bool = True


# The services offered in "add account". max_accounts is a starting value the
# user changes in the UI.
DEFAULT_CATEGORIES: list[Category] = [
    Category(
        id="facebook",
        name="فیسبوک",
        login_url="https://www.facebook.com/login",
        domains=["facebook.com", "www.facebook.com"],
        session_cookies=["c_user", "xs"],
        max_accounts=2,
        color="blue",
    ),
    Category(
        id="x",
        name="ایکس (ټویټر)",
        login_url="https://x.com/i/flow/login",
        domains=["x.com", "twitter.com"],
        session_cookies=["auth_token", "ct0"],
        max_accounts=3,
        color="gray",
    ),
    Category(
        id="instagram",
        name="انسټاګرام",
        login_url="https://www.instagram.com/accounts/login/",
        domains=["instagram.com", "www.instagram.com"],
        session_cookies=["sessionid", "ds_user_id"],
        max_accounts=1,
        color="pink",
    ),
    Category(
        id="google",
        name="ګوګل",
        login_url="https://accounts.google.com/signin",
        domains=["google.com", "accounts.google.com", "mail.google.com"],
        session_cookies=["SID", "SSID", "__Secure-1PSID"],
        max_accounts=2,
        color="orange",
    ),
    Category(
        id="linkedin",
        name="لینکډان",
        login_url="https://www.linkedin.com/login",
        domains=["linkedin.com", "www.linkedin.com"],
        session_cookies=["li_at"],
        max_accounts=1,
        color="teal",
    ),
    Category(
        id="youtube",
        name="یوټیوب",
        login_url="https://accounts.google.com/ServiceLogin?service=youtube",
        domains=["youtube.com", "www.youtube.com", "google.com"],
        session_cookies=["SID", "__Secure-1PSID", "LOGIN_INFO"],
        max_accounts=2,
        color="pink",
    ),
    Category(
        id="tiktok",
        name="ټیک ټاک",
        login_url="https://www.tiktok.com/login",
        domains=["tiktok.com", "www.tiktok.com"],
        session_cookies=["sessionid", "sid_tt"],
        max_accounts=1,
        color="purple",
    ),
    Category(
        id="telegram",
        name="ټلګرام وېب",
        login_url="https://web.telegram.org/",
        domains=["telegram.org", "web.telegram.org"],
        session_cookies=["stel_token", "stel_ssid"],
        max_accounts=1,
        color="teal",
    ),
    Category(
        id="other",
        name="بل سایټ",
        login_url="",
        domains=[],
        session_cookies=[],
        max_accounts=5,
        color="gray",
    ),
]

READY = "ready"
PENDING = "pending"
EXPIRED = "expired"

# Whether the saved cookies still open the site. "unknown" is the honest
# starting point: nothing has checked yet, or the check could not run (no
# internet, no browser).
ALIVE = "alive"
DEAD = "dead"
CHECKING = "checking"
UNKNOWN = "unknown"


class Account(BaseModel):
    id: str = Field(default_factory=lambda: new_id("acc"))
    category: str
    label: str = ""
    # Whatever the site shows as the signed-in name, when we can read it.
    display_name: str = ""
    login_url: str = ""
    status: str = PENDING
    cookie_count: int = 0
    # alive | dead | checking | unknown — see check_cookies().
    cookie_state: str = UNKNOWN
    cookie_checked_at: int | None = None
    cookie_note: str = ""
    # Which proxy this account goes out through. "" with proxy_mode "fixed"
    # means no proxy at all.
    proxy_id: str = ""
    # none  — always this machine's own address
    # fixed — always proxy_id
    # random— a different usable proxy each run (see the note in the UI: a
    #         stable address is safer, this is for people who want it anyway)
    proxy_mode: str = "none"
    created_at: int = Field(default_factory=lambda: int(time.time() * 1000))
    updated_at: int = Field(default_factory=lambda: int(time.time() * 1000))
    last_used_at: int | None = None

    @property
    def profile_dir(self) -> Path:
        return config.ACCOUNTS_DIR / "profiles" / self.id

    @property
    def cookie_file(self) -> Path:
        return config.ACCOUNTS_DIR / "cookies" / f"{self.id}.json"

    def summary(self) -> dict[str, Any]:
        return {
            **self.model_dump(),
            "profile_dir": str(self.profile_dir),
            "has_cookies": self.cookie_file.exists(),
        }


class AccountLimitReached(RuntimeError):
    pass


class AccountStore:
    """accounts.json plus one cookie file per account."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else config.ACCOUNTS_DIR / "accounts.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        (self.path.parent / "cookies").mkdir(parents=True, exist_ok=True)
        (self.path.parent / "profiles").mkdir(parents=True, exist_ok=True)
        self._accounts: list[Account] | None = None
        self._categories: list[Category] | None = None

    # ------------------------------------------------------------------ load

    def _load(self) -> None:
        if self._accounts is not None and self._categories is not None:
            return
        data: dict[str, Any] = {}
        if self.path.exists():
            try:
                data = json.loads(self.path.read_text("utf-8"))
            except Exception:  # noqa: BLE001 - a broken file falls back to defaults
                data = {}

        self._accounts = []
        for raw in data.get("accounts", []):
            try:
                self._accounts.append(Account.model_validate(raw))
            except Exception:  # noqa: BLE001
                continue

        # Categories keep the defaults but remember the user's limits.
        overrides = {c.get("id"): c for c in data.get("categories", [])}
        self._categories = []
        for default in DEFAULT_CATEGORIES:
            override = overrides.get(default.id) or {}
            category = default.model_copy()
            if isinstance(override.get("max_accounts"), int):
                category.max_accounts = max(1, min(override["max_accounts"], 20))
            if isinstance(override.get("enabled"), bool):
                category.enabled = override["enabled"]
            self._categories.append(category)

    def _save(self) -> None:
        self._load()
        payload = {
            "accounts": [a.model_dump() for a in self._accounts or []],
            "categories": [
                {"id": c.id, "max_accounts": c.max_accounts, "enabled": c.enabled}
                for c in self._categories or []
            ],
        }
        _atomic_write(self.path, json.dumps(payload, ensure_ascii=False, indent=2))

    # -------------------------------------------------------------- reading

    def categories(self) -> list[Category]:
        self._load()
        return list(self._categories or [])

    def category(self, category_id: str) -> Category | None:
        for category in self.categories():
            if category.id == category_id:
                return category
        return None

    def accounts(self, category: str | None = None) -> list[Account]:
        self._load()
        items = list(self._accounts or [])
        if category:
            items = [a for a in items if a.category == category]
        items.sort(key=lambda a: a.created_at)
        return items

    def get(self, account_id: str) -> Account | None:
        for account in self.accounts():
            if account.id == account_id:
                return account
        return None

    def count(self, category: str) -> int:
        return len([a for a in self.accounts(category) if a.status != PENDING])

    def overview(self) -> dict[str, Any]:
        categories = []
        for category in self.categories():
            used = self.count(category.id)
            categories.append(
                {
                    **category.model_dump(),
                    "used": used,
                    "full": used >= category.max_accounts,
                }
            )
        return {
            "categories": categories,
            "accounts": [a.summary() for a in self.accounts()],
        }

    # -------------------------------------------------------------- writing

    def create(self, category_id: str, label: str = "") -> Account:
        category = self.category(category_id)
        if category is None:
            raise KeyError(category_id)
        if self.count(category_id) >= category.max_accounts:
            raise AccountLimitReached(
                f"د «{category.name}» لپاره تر {category.max_accounts} اکاونټه "
                "زیات نه شي کېدای. لومړی حد لوړ کړئ یا یو اکاونټ ړنګ کړئ."
            )
        account = Account(
            category=category_id,
            label=label or f"{category.name} {self.count(category_id) + 1}",
            login_url=category.login_url,
        )
        self._load()
        assert self._accounts is not None
        self._accounts.append(account)
        self._save()
        return account

    def update(self, account_id: str, **changes: Any) -> Account | None:
        account = self.get(account_id)
        if account is None:
            return None
        for field, value in changes.items():
            if value is not None and hasattr(account, field):
                setattr(account, field, value)
        account.updated_at = int(time.time() * 1000)
        self._save()
        return account

    def delete(self, account_id: str) -> bool:
        account = self.get(account_id)
        if account is None:
            return False
        self._load()
        assert self._accounts is not None
        self._accounts = [a for a in self._accounts if a.id != account_id]
        self._save()

        if account.cookie_file.exists():
            account.cookie_file.unlink()
        _remove_tree(account.profile_dir)
        return True

    def set_limit(self, category_id: str, max_accounts: int) -> Category | None:
        self._load()
        for category in self._categories or []:
            if category.id == category_id:
                category.max_accounts = max(1, min(int(max_accounts), 20))
                self._save()
                return category
        return None

    # -------------------------------------------------------------- cookies

    def save_cookies(self, account_id: str, cookies: list[dict]) -> int:
        account = self.get(account_id)
        if account is None:
            return 0
        account.cookie_file.parent.mkdir(parents=True, exist_ok=True)
        _atomic_write(
            account.cookie_file,
            json.dumps(cookies, ensure_ascii=False, indent=2),
            private=True,
        )
        self.update(
            account_id,
            cookie_count=len(cookies),
            status=READY if cookies else PENDING,
        )
        return len(cookies)

    def load_cookies(self, account_id: str) -> list[dict]:
        account = self.get(account_id)
        if account is None or not account.cookie_file.exists():
            return []
        try:
            data = json.loads(account.cookie_file.read_text("utf-8"))
            return data if isinstance(data, list) else []
        except Exception:  # noqa: BLE001
            return []

    def set_proxy(
        self, account_id: str, proxy_id: str = "", mode: str = "fixed"
    ) -> Account | None:
        """Give this account its own way out to the internet."""
        account = self.get(account_id)
        if account is None:
            return None
        account.proxy_id = proxy_id
        account.proxy_mode = mode if (proxy_id or mode != "fixed") else "none"
        account.updated_at = int(time.time() * 1000)
        self._save()
        return account

    def assignments(self) -> dict[str, str]:
        """account id → proxy id, for the accounts that have one."""
        return {
            a.id: a.proxy_id
            for a in self.accounts()
            if a.proxy_mode == "fixed" and a.proxy_id
        }

    def forget_proxy(self, proxy_id: str) -> int:
        """A deleted proxy must not stay attached to anybody."""
        touched = 0
        for account in self.accounts():
            if account.proxy_id == proxy_id:
                account.proxy_id = ""
                account.proxy_mode = "none"
                touched += 1
        if touched:
            self._save()
        return touched

    def set_cookie_state(
        self, account_id: str, state: str, note: str = ""
    ) -> Account | None:
        """Record what the liveness check found."""
        changes: dict[str, Any] = {"cookie_state": state, "cookie_note": note}
        if state != CHECKING:
            changes["cookie_checked_at"] = int(time.time() * 1000)
        return self.update(account_id, **changes)

    def mark_used(self, account_id: str) -> None:
        self.update(account_id, last_used_at=int(time.time() * 1000))


def has_session(cookies: list[dict], category: Category) -> bool:
    """True when the cookies carry one of the site's session tokens."""
    if not category.session_cookies:
        return bool(cookies)
    names = {c.get("name") for c in cookies}
    return any(name in names for name in category.session_cookies)


def belongs_to(cookie: dict, category: Category) -> bool:
    domain = str(cookie.get("domain") or "").lstrip(".").lower()
    if not category.domains:
        return True
    return any(domain == d or domain.endswith("." + d) for d in category.domains)


def _atomic_write(path: Path, text: str, private: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        if private:
            # Session tokens: readable only by the owner.
            os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def _remove_tree(path: Path) -> None:
    import shutil

    try:
        if path.exists():
            shutil.rmtree(path, ignore_errors=True)
    except Exception:  # noqa: BLE001
        pass
