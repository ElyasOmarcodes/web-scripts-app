"""An account's own username and password, kept locally and kept closed.

The app signs in with cookies and normally never needs these. But a cookie
eventually dies, and when it does the user has to sign in again — so having
the username and password to hand, on their own machine, saves hunting through
a notebook. That convenience is only acceptable if the file is useless to
anyone who copies it.

So nothing here is stored in the clear. Each account's details are sealed with
the vault's master key; the file holds only the sealed bytes plus the few
facts the UI needs in order to draw a row — that something *is* saved, and
when it was last changed. Reading the details back needs the vault open **and**
the password typed again, because opening the app in the morning is not the
same as asking for a password to be put on screen.
"""

from __future__ import annotations

import json
import os
import stat
import tempfile
import time
from pathlib import Path
from typing import Any

from . import config
from .vault import Locked, Vault, VaultError


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(text)
        os.replace(temporary, path)
        try:
            path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class CredentialStore:
    def __init__(self, vault: Vault, path: Path | None = None) -> None:
        self.vault = vault
        self.path = Path(path) if path else config.ACCOUNTS_DIR / "credentials.json"
        self._data: dict[str, Any] | None = None

    # ------------------------------------------------------------- on disk

    def _load(self) -> dict[str, Any]:
        if self._data is None:
            if self.path.exists():
                try:
                    self._data = json.loads(self.path.read_text("utf-8"))
                except Exception:  # noqa: BLE001
                    self._data = {}
            else:
                self._data = {}
        self._data.setdefault("accounts", {})
        return self._data

    def _save(self) -> None:
        _atomic_write(
            self.path, json.dumps(self._load(), ensure_ascii=False, indent=2)
        )

    def reload(self) -> None:
        self._data = None

    # -------------------------------------------------------------- public

    def summary(self, account_id: str) -> dict[str, Any]:
        """What may be shown without anybody proving anything."""
        entry = self._load()["accounts"].get(account_id) or {}
        return {
            "has_username": bool(entry.get("has_username")),
            "has_password": bool(entry.get("has_password")),
            "has_note": bool(entry.get("has_note")),
            "updated_at": entry.get("updated_at"),
        }

    def saved(self) -> set[str]:
        return {
            account_id
            for account_id, entry in self._load()["accounts"].items()
            if entry.get("has_username") or entry.get("has_password")
        }

    def set(
        self,
        account_id: str,
        username: str = "",
        password: str = "",
        note: str = "",
    ) -> dict[str, Any]:
        """Save (or clear) an account's details. The vault must be open."""
        accounts = self._load()["accounts"]
        if not (username or password or note):
            accounts.pop(account_id, None)
            self._save()
            return self.summary(account_id)
        sealed = self.vault.encrypt_json(
            {"username": username, "password": password, "note": note}
        )
        accounts[account_id] = {
            **sealed,
            "has_username": bool(username),
            "has_password": bool(password),
            "has_note": bool(note),
            "updated_at": int(time.time() * 1000),
        }
        self._save()
        return self.summary(account_id)

    def reveal(self, account_id: str) -> dict[str, str]:
        """The details themselves. Only ever called after a fresh password."""
        entry = self._load()["accounts"].get(account_id)
        if not entry:
            return {"username": "", "password": "", "note": ""}
        try:
            opened = self.vault.decrypt_json(entry)
        except Locked:
            # A closed app is not a damaged entry: say so, so the caller can
            # ask for the password instead of reporting corruption.
            raise
        except VaultError:
            return {"username": "", "password": "", "note": "",
                    "error": "معلومات ونه پرانیستل شول"}
        return {
            "username": str(opened.get("username", "")),
            "password": str(opened.get("password", "")),
            "note": str(opened.get("note", "")),
        }

    def delete(self, account_id: str) -> None:
        self._load()["accounts"].pop(account_id, None)
        self._save()
