"""The lock on the front door, and the key everything secret is kept under.

The app holds things worth stealing: session cookies that *are* the login,
proxy passwords, and — from now on — the accounts' own usernames and
passwords. Anyone who can open the folder can read them. So there is a lock.

**One key, several doors.** A random 32-byte *master key* is generated once
and never leaves this machine. Every secret in the app is encrypted with it.
The key itself is then stored several times over, each copy wrapped by one way
of proving who you are:

* the app's own password — always present, and always the way back in;
* the Windows account password — optional, verified by Windows itself;
* the fingerprint — optional, released by Windows Hello.

Enabling a second door never replaces the first. If the Windows password were
the only way in, changing it in Windows would lock the user out of their own
accounts for good — so the app's password stays as the way home, and the UI
says so rather than letting someone find out the hard way.

**What is stored.** Never the password. A wrapped copy of the master key, and
one small blob that decrypts to a known word — that is how a wrong password is
told from a right one, without the password being on disk in any form.
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import stat
import tempfile
import time
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from . import config, winauth

# scrypt, the memory-hard one: a guess costs 32 MB of memory as well as time,
# which is what makes a stolen file expensive to attack offline.
# maxmem has to be raised by hand: OpenSSL refuses anything over 32 MB unless
# it is told otherwise, and 32 MB is exactly what these parameters need.
KDF = {"n": 2 ** 15, "r": 8, "p": 1, "dklen": 32, "maxmem": 96 * 1024 * 1024}
PROOF = b"WebScripts-vault-v1"

PASSWORD = "password"
WINDOWS = "windows"
BIOMETRIC = "biometric"

MIN_LENGTH = 6

# After this many wrong tries in a row, every further try is slowed down. A
# local app cannot lock itself out — that would hand anybody a way to deny the
# owner their own accounts — but it can make guessing pointlessly slow.
FREE_ATTEMPTS = 5
MAX_DELAY = 5.0


class VaultError(RuntimeError):
    """Something the user should be told, in their own words."""


class Locked(VaultError):
    pass


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(text)
        os.replace(temporary, path)
        try:
            path.chmod(stat.S_IRUSR | stat.S_IWUSR)  # nobody else, not even a group
        except OSError:
            pass
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _derive(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, **KDF)


def _seal(key: bytes, data: bytes) -> dict[str, str]:
    nonce = secrets.token_bytes(12)
    return {
        "nonce": winauth.b64(nonce),
        "blob": winauth.b64(AESGCM(key).encrypt(nonce, data, None)),
    }


def _open(key: bytes, sealed: dict[str, str]) -> bytes | None:
    try:
        return AESGCM(key).decrypt(
            winauth.unb64(sealed["nonce"]), winauth.unb64(sealed["blob"]), None
        )
    except Exception:  # noqa: BLE001 - a wrong key is a normal answer here
        return None


class Vault:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else config.BASE_DIR / "security.json"
        self._data: dict[str, Any] | None = None
        self._key: bytes | None = None  # the master key, only while unlocked
        self._failures = 0

    # ------------------------------------------------------------- on disk

    def _load(self) -> dict[str, Any]:
        if self._data is None:
            if self.path.exists():
                try:
                    self._data = json.loads(self.path.read_text("utf-8"))
                except Exception:  # noqa: BLE001 - a broken file is no lock
                    self._data = {}
            else:
                self._data = {}
        return self._data

    def _save(self) -> None:
        _atomic_write(
            self.path, json.dumps(self._load(), ensure_ascii=False, indent=2)
        )

    def reload(self) -> None:
        self._data = None

    # -------------------------------------------------------------- state

    @property
    def configured(self) -> bool:
        return bool(self._load().get("wrappers", {}).get(PASSWORD))

    @property
    def locked(self) -> bool:
        return self.configured and self._key is None

    def state(self) -> dict[str, Any]:
        data = self._load()
        wrappers = data.get("wrappers", {})
        reader = winauth.biometrics()
        return {
            "configured": self.configured,
            "locked": self.locked,
            "windows_user": winauth.account_name(),
            "windows_available": winauth.IS_WINDOWS,
            "windows_enabled": bool(wrappers.get(WINDOWS)),
            "biometric_state": reader["state"],
            "biometric_message": reader["message"],
            # The raw reason, for when the answer is "could not tell".
            "biometric_detail": reader.get("detail", ""),
            "biometric_enabled": bool(wrappers.get(BIOMETRIC)),
            "created_at": data.get("created_at"),
            "changed_at": data.get("changed_at"),
            "min_length": MIN_LENGTH,
        }

    # -------------------------------------------------------- setting up

    def setup(
        self,
        password: str,
        use_windows_password: bool = False,
        windows_password: str = "",
        use_biometric: bool = False,
    ) -> dict[str, Any]:
        """First run: make the key and lock it behind this password."""
        if self.configured:
            raise VaultError("پټنوم لا دمخه ټاکل شوی دی.")
        self._require_strong(password)

        master = secrets.token_bytes(32)
        data = self._load()
        data.clear()
        data.update({
            "version": 1,
            "created_at": int(time.time() * 1000),
            "wrappers": {PASSWORD: self._wrap_password(master, password)},
            "check": _seal(master, PROOF),
        })
        self._key = master
        self._save()

        report = {"windows": False, "biometric": False, "notes": []}
        if use_windows_password:
            try:
                self.set_windows_password(True, windows_password)
                report["windows"] = True
            except VaultError as error:
                report["notes"].append(str(error))
        if use_biometric:
            try:
                self.set_biometric(True)
                report["biometric"] = True
            except VaultError as error:
                report["notes"].append(str(error))
        return report

    def _require_strong(self, password: str) -> None:
        if len(password or "") < MIN_LENGTH:
            raise VaultError(f"پټنوم باید لږ تر لږه {MIN_LENGTH} تورې ولري.")

    def _wrap_password(self, master: bytes, password: str) -> dict[str, Any]:
        salt = secrets.token_bytes(16)
        sealed = _seal(_derive(password, salt), master)
        return {"salt": winauth.b64(salt), **sealed}

    # ---------------------------------------------------------- unlocking

    def unlock(self, password: str = "", method: str = PASSWORD) -> bool:
        master = self._master_from(password, method)
        if master is None:
            self._punish()
            return False
        self._failures = 0
        self._key = master
        return True

    def verify(self, password: str = "", method: str = PASSWORD) -> bool:
        """Prove it is really them, without changing whether the app is open.

        Used by everything that shows a secret: opening the app once is not
        the same as being allowed to read a password off the screen.
        """
        if not self.configured:
            return True
        master = self._master_from(password, method)
        if master is None:
            self._punish()
            return False
        self._failures = 0
        if self._key is None:
            self._key = master
        return True

    def _master_from(self, password: str, method: str) -> bytes | None:
        data = self._load()
        wrappers = data.get("wrappers", {})
        check = data.get("check")

        if method == BIOMETRIC:
            wrapper = wrappers.get(BIOMETRIC)
            if not wrapper:
                return None
            if not winauth.verify_biometric("WebScripts — د ګوتې نښه"):
                return None
            master = winauth.unprotect(winauth.unb64(wrapper["blob"]))
        elif method == WINDOWS:
            wrapper = wrappers.get(WINDOWS)
            if not wrapper or not winauth.check_password(password):
                return None
            master = _open(
                _derive(password, winauth.unb64(wrapper["salt"])), wrapper
            )
        else:
            wrapper = wrappers.get(PASSWORD)
            if not wrapper or not password:
                return None
            master = _open(
                _derive(password, winauth.unb64(wrapper["salt"])), wrapper
            )

        if not master or not check or _open(master, check) != PROOF:
            return None
        return master

    def _punish(self) -> None:
        self._failures += 1
        extra = self._failures - FREE_ATTEMPTS
        if extra > 0:
            time.sleep(min(MAX_DELAY, 0.4 * extra))

    def lock(self) -> None:
        self._key = None

    # ------------------------------------------------------------ changing

    def change_password(self, current: str, new: str) -> None:
        if not self.configured:
            raise VaultError("لا پټنوم نه دی ټاکل شوی.")
        self._require_strong(new)
        master = self._master_from(current, PASSWORD)
        if master is None:
            self._punish()
            raise VaultError("اوسنی پټنوم سم نه دی.")
        data = self._load()
        data["wrappers"][PASSWORD] = self._wrap_password(master, new)
        data["changed_at"] = int(time.time() * 1000)
        self._key = master
        self._save()

    def set_windows_password(self, enabled: bool, windows_password: str = "") -> None:
        """Let the Windows account password open the app as well."""
        data = self._load()
        if not enabled:
            data.get("wrappers", {}).pop(WINDOWS, None)
            self._save()
            return
        if not winauth.IS_WINDOWS:
            raise VaultError("دا امکان یوازې په ویندوز کې شته.")
        master = self._unlocked_key()
        if not winauth.check_password(windows_password):
            raise VaultError(
                "د ویندوز پټنوم سم نه دی — ویندوز پخپله یې ونه مانه."
            )
        salt = secrets.token_bytes(16)
        data.setdefault("wrappers", {})[WINDOWS] = {
            "salt": winauth.b64(salt),
            "user": winauth.account_name(),
            **_seal(_derive(windows_password, salt), master),
        }
        self._save()

    def set_biometric(self, enabled: bool) -> None:
        """Let Windows Hello open the app.

        Hello answers yes or no; it cannot produce a key. So the master key is
        kept here under Windows' own encryption, which is tied to this Windows
        account, and handed over only after Hello has said yes.

        Turning it on **asks Windows to read the finger**, rather than asking
        Windows whether it could. Those are different questions, and the
        second one is answered wrongly often enough — on machines whose owner
        unlocks them with that very reader every morning — that it is not
        allowed to have the last word here.
        """
        data = self._load()
        if not enabled:
            data.get("wrappers", {}).pop(BIOMETRIC, None)
            self._save()
            return
        if not winauth.IS_WINDOWS:
            raise VaultError("دا امکان یوازې په ویندوز کې شته.")
        master = self._unlocked_key()
        if not winauth.verify_biometric("WebScripts — ګوته فعالول"):
            reader = winauth.biometrics()
            raise VaultError(
                "ویندوز ګوته ونه منله. " + (reader.get("message") or "")
            )
        protected = winauth.protect(master)
        if protected is None:
            raise VaultError("ویندوز د کیلي ساتل ونه منل.")
        data.setdefault("wrappers", {})[BIOMETRIC] = {
            "blob": winauth.b64(protected)
        }
        self._save()

    def reset(self) -> None:
        """Forget everything. Every encrypted secret becomes unreadable."""
        self._data = {}
        self._key = None
        if self.path.exists():
            self.path.unlink()

    # -------------------------------------------------------- using the key

    def _unlocked_key(self) -> bytes:
        if self._key is None:
            raise Locked("لومړی پروګرام خلاص کړئ.")
        return self._key

    def encrypt(self, data: bytes) -> dict[str, str]:
        return _seal(self._unlocked_key(), data)

    def decrypt(self, sealed: dict[str, str]) -> bytes:
        opened = _open(self._unlocked_key(), sealed)
        if opened is None:
            raise VaultError("معلومات ونه پرانیستل شول.")
        return opened

    def encrypt_json(self, value: Any) -> dict[str, str]:
        return self.encrypt(json.dumps(value, ensure_ascii=False).encode("utf-8"))

    def decrypt_json(self, sealed: dict[str, str]) -> Any:
        return json.loads(self.decrypt(sealed).decode("utf-8"))


vault = Vault()
