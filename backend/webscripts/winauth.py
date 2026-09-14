"""What the computer itself can prove about the person sitting at it.

Three things, all Windows-only and all optional — on any other system, and on
a Windows without the hardware, every function here answers "no" instead of
raising, so the app simply falls back to its own password.

* **the Windows account password** — checked by asking Windows to log in with
  it (``LogonUser``). Nothing is stored: the password is verified and thrown
  away, and only a key derived from it stays behind.
* **the fingerprint reader** — Windows Hello. Windows will say whether a
  reader exists, whether a fingerprint is enrolled, and whether the person in
  front of it is the account's owner. It never hands over a key, only a yes.
* **DPAPI** — Windows' own encryption, tied to the signed-in account. Used to
  keep the vault key for the Hello route, because Hello answers yes/no and
  cannot produce a key of its own.

Because Hello gives a yes rather than a key, the fingerprint route is exactly
as strong as the Windows account behind it — which is the honest description,
and the one the UI gives.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from typing import Any

IS_WINDOWS = sys.platform.startswith("win")

# What the fingerprint reader can do here.
NO_HARDWARE = "no_hardware"      # no reader at all → the option is disabled
NOT_ENROLLED = "not_enrolled"    # a reader, but no finger registered yet
READY = "ready"
NOT_WINDOWS = "not_windows"
# Windows would not answer the question — PowerShell missing, WinRT refusing
# to load, the call timing out. It does **not** mean there is no reader: a
# machine whose power button reads fingerprints every morning can land here.
# So the option stays offered, and the way to settle it is to try it.
UNCERTAIN = "uncertain"


def account_name() -> str:
    return os.environ.get("USERNAME") or os.environ.get("USER") or ""


# ------------------------------------------------------- the Windows password


def check_password(password: str, user: str = "", domain: str = ".") -> bool:
    """True when this really is the Windows password of the signed-in user.

    Windows is asked to perform a network-style logon with it. Nothing is
    written, nothing is kept, and a wrong password simply returns False.
    """
    if not IS_WINDOWS or not password:
        return False
    try:
        import ctypes
        from ctypes import wintypes

        LOGON32_LOGON_NETWORK = 3
        LOGON32_PROVIDER_DEFAULT = 0

        advapi = ctypes.WinDLL("advapi32", use_last_error=True)
        advapi.LogonUserW.argtypes = [
            wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.LPCWSTR,
            wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE),
        ]
        advapi.LogonUserW.restype = wintypes.BOOL

        token = wintypes.HANDLE()
        ok = advapi.LogonUserW(
            user or account_name(), domain, password,
            LOGON32_LOGON_NETWORK, LOGON32_PROVIDER_DEFAULT,
            ctypes.byref(token),
        )
        if ok and token:
            ctypes.WinDLL("kernel32").CloseHandle(token)
        return bool(ok)
    except Exception:  # noqa: BLE001 - a locked-down machine simply says no
        return False


# ------------------------------------------------------------------- DPAPI


def protect(data: bytes, label: str = "WebScripts") -> bytes | None:
    """Encrypt with the Windows account's own key. None when unavailable."""
    return _dpapi(data, label, unprotect=False)


def unprotect(data: bytes, label: str = "WebScripts") -> bytes | None:
    return _dpapi(data, label, unprotect=True)


def _dpapi(data: bytes, label: str, unprotect: bool) -> bytes | None:
    if not IS_WINDOWS or not data:
        return None
    try:
        import ctypes
        from ctypes import wintypes

        class BLOB(ctypes.Structure):
            _fields_ = [("cbData", wintypes.DWORD),
                        ("pbData", ctypes.POINTER(ctypes.c_char))]

        def to_blob(raw: bytes) -> BLOB:
            buffer = ctypes.create_string_buffer(raw, len(raw))
            return BLOB(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))

        crypt = ctypes.WinDLL("crypt32", use_last_error=True)
        source = to_blob(data)
        result = BLOB()
        function = crypt.CryptUnprotectData if unprotect else crypt.CryptProtectData
        if unprotect:
            ok = function(ctypes.byref(source), None, None, None, None, 0,
                          ctypes.byref(result))
        else:
            ok = function(ctypes.byref(source), label, None, None, None, 0,
                          ctypes.byref(result))
        if not ok:
            return None
        try:
            return ctypes.string_at(result.pbData, result.cbData)
        finally:
            ctypes.WinDLL("kernel32").LocalFree(result.pbData)
    except Exception:  # noqa: BLE001
        return None


# ------------------------------------------------------------ Windows Hello

# Windows PowerShell first — it is the one that can load WinRT types without
# help. PowerShell 7 is tried second, for machines where the old one is gone.
_SHELLS = ("powershell", "powershell.exe", "pwsh")
_ARGUMENTS = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
              "-Command"]

# Windows answers 0 = ready, 1 = no reader, 2 = no finger enrolled,
# 3 = disabled by policy, 4 = the device is not ready.
_AVAILABILITY = r"""
$ErrorActionPreference='Stop'
try {
  [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime] | Out-Null
  $task = [Windows.Security.Credentials.UI.UserConsentVerifier]::CheckAvailabilityAsync()
  $method = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'GetAwaiter' -and $_.GetParameters().Count -eq 1 } |
      Select-Object -First 1).MakeGenericMethod([Windows.Security.Credentials.UI.UserConsentVerifierAvailability])
  $result = $method.Invoke($null, @($task)).GetResult()
  Write-Output ('{"availability":' + [int]$result + '}')
} catch { Write-Output '{"availability":-1}' }
"""

# The hardware list, as a second opinion when WinRT will not load.
_DEVICES = r"""
$ErrorActionPreference='Stop'
try {
  $found = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
             Where-Object { $_.PNPClass -eq 'Biometric' })
  Write-Output ('{"devices":' + $found.Count + '}')
} catch { Write-Output '{"devices":-1}' }
"""

_VERIFY = r"""
$ErrorActionPreference='Stop'
try {
  [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime] | Out-Null
  $task = [Windows.Security.Credentials.UI.UserConsentVerifier]::RequestVerificationAsync('%(message)s')
  $method = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'GetAwaiter' -and $_.GetParameters().Count -eq 1 } |
      Select-Object -First 1).MakeGenericMethod([Windows.Security.Credentials.UI.UserConsentVerificationResult])
  $result = $method.Invoke($null, @($task)).GetResult()
  Write-Output ('{"verified":' + [int]$result + '}')
} catch { Write-Output '{"verified":-1}' }
"""


def _powershell(script: str, timeout: float) -> dict[str, Any]:
    """Run a snippet in whichever PowerShell this machine has."""
    last = ""
    for shell in _SHELLS:
        try:
            finished = subprocess.run(
                [shell, *_ARGUMENTS, script],
                capture_output=True, text=True, timeout=timeout,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        except FileNotFoundError:
            continue  # not this one; try the next
        except Exception as error:  # noqa: BLE001 - it hung, or was blocked
            last = f"{shell}: {error}"
            continue
        for line in reversed((finished.stdout or "").strip().splitlines()):
            line = line.strip()
            if line.startswith("{"):
                try:
                    return json.loads(line)
                except ValueError:
                    continue
        last = (finished.stderr or "").strip().splitlines()[:1] or [""]
        last = f"{shell}: {last[0][:160]}"
    return {"_error": last} if last else {}


def readers() -> int:
    """How many biometric devices Windows lists, or -1 when it would not say.

    A second opinion for when WinRT will not load: the device is in the
    hardware list whether or not an API is willing to talk about it.
    """
    answer = _powershell(_DEVICES, timeout=30)
    count = answer.get("devices")
    return int(count) if isinstance(count, int) else -1


def biometrics() -> dict[str, Any]:
    """Whether a fingerprint can be used here, and why not when it cannot."""
    if not IS_WINDOWS:
        return {
            "state": NOT_WINDOWS,
            "message": "د ګوتې نښه یوازې په ویندوز کې کار کوي.",
            "detail": "",
        }
    answer = _powershell(_AVAILABILITY, timeout=45)
    code = answer.get("availability", -1)
    if code == 0:
        return {"state": READY, "message": "ویندوز هیلو چمتو ده.", "detail": ""}
    if code == 2:
        return {
            "state": NOT_ENROLLED,
            "message": "لوستونکی شته، خو تر اوسه مو ګوته نه ده ثبت کړې. "
                       "د ویندوز په تنظیماتو کې یې ثبت کړئ، بیا دلته فعاله کړئ.",
            "detail": "",
        }
    if code in (1, 3, 4):
        # Windows answered, and the answer was no.
        found = readers()
        if found > 0:
            # …but the hardware list disagrees. Do not argue with the user's
            # own morning: offer it, and let one touch settle it.
            return {
                "state": UNCERTAIN,
                "message": "ویندوز هیلو ووایه چې چمتو نه ده، خو د ګوتې "
                           "لوستونکی په کمپیوټر کې شته. یو ځل یې وازمویئ — "
                           "که ګوته ومنل شوه، فعالېږي.",
                "detail": f"CheckAvailability={code}, devices={found}",
            }
        return {
            "state": NO_HARDWARE,
            "message": "پدې کمپیوټر کې د ګوتې لوستونکی نشته یا فعال نه دی.",
            "detail": f"CheckAvailability={code}",
        }

    # Windows would not answer at all. That is our problem, not the machine's.
    found = readers()
    if found != 0:
        return {
            "state": UNCERTAIN,
            "message": "و نه شو کتلی چې ویندوز هیلو چمتو ده که نه — یو ځل یې "
                       "وازمویئ. که ستاسو ګوته ومنل شوه، فعالېږي.",
            "detail": str(answer.get("_error") or f"devices={found}")[:200],
        }
    return {
        "state": NO_HARDWARE,
        "message": "پدې کمپیوټر کې د ګوتې لوستونکی ونه موندل شو.",
        "detail": str(answer.get("_error") or "")[:200],
    }


def verify_biometric(message: str = "WebScripts") -> bool:
    """Ask Windows to confirm the person. 0 means it did."""
    if not IS_WINDOWS:
        return False
    safe = message.replace("'", "").replace("\n", " ")[:80]
    answer = _powershell(_VERIFY % {"message": safe}, timeout=90)
    return answer.get("verified") == 0


def open_enrollment() -> bool:
    """Open the Windows page where a fingerprint is registered.

    Enrolling is the operating system's job — no application is allowed to do
    it — so the most an app can honestly offer is to take the user there.
    """
    if not IS_WINDOWS:
        return False
    try:
        os.startfile("ms-settings:signinoptions")  # type: ignore[attr-defined]
        return True
    except Exception:  # noqa: BLE001
        return False


def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def unb64(text: str) -> bytes:
    return base64.b64decode(text.encode("ascii"))
