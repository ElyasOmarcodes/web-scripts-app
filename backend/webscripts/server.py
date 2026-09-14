"""HTTP + WebSocket API consumed by the Flutter desktop UI."""

from __future__ import annotations

import asyncio
import platform
import threading
import time
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import browsers, config, exporting, fingerprints, netcheck
from .accounts import AccountLimitReached, AccountStore
from .credentials import CredentialStore
from .lifetime import Lifetime, exit_now
from .machine import estimate, machine
from .models import Script, Step, Variable, new_id
from .session import SessionBusy, SessionManager
from .settings import Settings, SettingsStore
from .storage import Storage
from .proxies import ProxyStore, parse_many
from .tasks import TaskStore
from .vault import Locked, Vault, VaultError

storage = Storage()
settings_store = SettingsStore()
account_store = AccountStore()
task_store = TaskStore()
proxy_store = ProxyStore()
vault = Vault()
credential_store = CredentialStore(vault)
manager = SessionManager(
    storage, settings_store, account_store, task_store, proxy_store
)

# Filled in by main(); the default one never exits on its own, which is what a
# developer running `python run_server.py` by hand wants.
lifetime = Lifetime(shutdown=lambda: None)

app = FastAPI(title="WebScripts API", version=config.VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Paths that answer while the app is locked: the lock screen itself, the
# health check the UI waits on before it can draw anything, and the shutdown
# the window calls when it closes — a locked app still has to be closable.
OPEN_WHILE_LOCKED = (
    "/api/health",
    "/api/security",
    "/api/shutdown",
)


@app.middleware("http")
async def require_unlocked(request, call_next):
    """Nothing but the lock screen answers while the vault is closed.

    The lock is only worth having if it is in front of the data rather than in
    front of the window: a locked app whose API still answers protects
    nothing from anyone who knows the port number.
    """
    path = request.url.path
    if (
        path.startswith("/api/")
        and not path.startswith(OPEN_WHILE_LOCKED)
        and vault.locked
    ):
        return JSONResponse(
            status_code=423,
            content={"detail": "پروګرام بند دی — لومړی یې پټنوم ورکړئ."},
        )
    return await call_next(request)


# ------------------------------------------------------------------ schemas


class RecordStart(BaseModel):
    name: str = "نوی سکریپټ"
    url: str = ""
    capture_scroll: bool | None = None
    script_id: str | None = None
    browser: str | None = None
    # Record as this saved account, so the site opens already signed in.
    account_id: str | None = None


class RunRequest(BaseModel):
    variables: dict[str, str] = Field(default_factory=dict)
    # Omitted values fall back to the saved settings.
    speed: float | None = None
    headless: bool | None = None
    keep_open: bool | None = None
    browser: str | None = None
    # Which saved account's session to run as.
    account_id: str | None = None


class LoginStart(BaseModel):
    category: str
    label: str = ""
    browser: str | None = None


class AccountPatch(BaseModel):
    label: str | None = None


class CategoryPatch(BaseModel):
    max_accounts: int | None = None


class TaskUpsert(BaseModel):
    """Everything a task holds; every field is optional on a PATCH."""

    name: str | None = None
    script_id: str | None = None
    account_ids: list[str] | None = None
    concurrency: int | None = Field(default=None, ge=1, le=32)
    browser: str | None = None
    speed: float | None = None
    headless: bool | None = None
    keep_open: bool | None = None
    stop_on_error: bool | None = None
    gap_seconds: float | None = Field(default=None, ge=0, le=600)
    variables: dict[str, str] | None = None
    note: str | None = None


class ProxyImport(BaseModel):
    """A pasted list, in whatever shape the seller wrote it."""

    text: str = ""
    label: str = ""


class ProxyPatch(BaseModel):
    label: str | None = None
    enabled: bool | None = None
    username: str | None = None
    password: str | None = None


class ProxyCheck(BaseModel):
    proxy_ids: list[str] | None = None


class VaultSetup(BaseModel):
    password: str = ""
    use_windows_password: bool = False
    windows_password: str = ""
    use_biometric: bool = False


class VaultUnlock(BaseModel):
    password: str = ""
    # password | windows | biometric
    method: str = "password"


class VaultPassword(BaseModel):
    current: str = ""
    new: str = ""


class VaultMethods(BaseModel):
    windows: bool | None = None
    windows_password: str = ""
    biometric: bool | None = None


class SecretSave(BaseModel):
    """Saving an account's own username and password."""

    # Proof, every time: opening the app in the morning is not permission to
    # write a password into it in the afternoon.
    code: str = ""
    method: str = "password"
    username: str = ""
    password: str = ""
    note: str = ""


class SecretReveal(BaseModel):
    code: str = ""
    method: str = "password"


class ExportRequest(BaseModel):
    code: str = ""
    method: str = "password"
    ids: list[str] | None = None
    # accounts/proxies: csv · scripts: json | py | js | csv
    format: str = "csv"
    # Passwords leave only when they are asked for by name.
    include_secrets: bool = False
    # And the cookies — the session itself — only when asked for separately,
    # because that column is the login, not a description of it.
    include_cookies: bool = False


class ImportRequest(BaseModel):
    code: str = ""
    method: str = "password"
    text: str = ""
    path: str = ""


class FingerprintAssign(BaseModel):
    fingerprint_id: str = ""


class ProxyAssign(BaseModel):
    # "" clears the assignment; mode is none | fixed | random.
    proxy_id: str = ""
    mode: str = "fixed"


class ProxyDistribute(BaseModel):
    account_ids: list[str] | None = None


class CookieCheck(BaseModel):
    # Empty means "every account".
    account_ids: list[str] | None = None


class TaskRun(BaseModel):
    # Continue from where it stopped instead of starting every account again.
    resume: bool = False


class ScriptUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    start_url: str | None = None
    steps: list[Step] | None = None
    variables: list[Variable] | None = None
    # This script's own random pause between two actions, in milliseconds.
    gap_min_ms: int | None = Field(default=None, ge=0, le=60_000)
    gap_max_ms: int | None = Field(default=None, ge=0, le=120_000)


# ------------------------------------------------------------------- routes


@app.get("/api/health")
def health() -> dict[str, Any]:
    try:
        active = browsers.resolve(settings_store.load().browser).to_dict()
    except browsers.BrowserNotFound as exc:
        active = {"error": str(exc)}
    return {
        "ok": True,
        "version": config.VERSION,
        "platform": platform.system(),
        "home": str(config.BASE_DIR),
        "profile": str(config.PROFILE_DIR),
        "state": manager.state,
        "browser": active,
    }


# ------------------------------------------------------------ settings


@app.get("/api/settings")
def get_settings() -> dict:
    return settings_store.load().model_dump()


@app.put("/api/settings")
def put_settings(payload: dict = Body(...)) -> dict:
    try:
        return settings_store.update(payload).model_dump()
    except Exception as exc:  # noqa: BLE001 - validation message goes to the UI
        raise HTTPException(400, f"ناسم تنظیم: {exc}") from None


@app.post("/api/settings/reset")
def reset_settings() -> dict:
    return settings_store.save(Settings()).model_dump()


@app.get("/api/browsers")
def list_browsers(refresh: bool = False) -> dict:
    found = browsers.detect(refresh=refresh)
    preferred = settings_store.load().browser
    try:
        active = browsers.resolve(preferred).id
    except browsers.BrowserNotFound:
        active = None
    return {
        "browsers": [b.to_dict() for b in found],
        "selected": preferred,
        "active": active,
    }


@app.get("/api/scripts")
def list_scripts() -> list[dict[str, Any]]:
    return [script.summary() for script in storage.list()]


@app.post("/api/scripts")
def create_script(payload: ScriptUpdate = Body(default_factory=ScriptUpdate)) -> dict:
    script = Script(
        name=payload.name or "نوی سکریپټ",
        description=payload.description or "",
        start_url=payload.start_url or "",
        steps=payload.steps or [],
        variables=payload.variables or [],
    )
    return storage.save(script).model_dump()


@app.get("/api/scripts/{script_id}")
def get_script(script_id: str) -> dict:
    script = storage.get(script_id)
    if script is None:
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    return script.model_dump()


@app.put("/api/scripts/{script_id}")
def update_script(script_id: str, payload: ScriptUpdate) -> dict:
    script = storage.get(script_id)
    if script is None:
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    # Assign the parsed objects (not dumped dicts) so the stored model keeps
    # its proper types. A field sent as null is a deliberate "unset me" —
    # that is how a script goes back to the app-wide pacing.
    clearable = {"gap_min_ms", "gap_max_ms"}
    for field in payload.model_fields_set:
        value = getattr(payload, field)
        if value is not None or field in clearable:
            setattr(script, field, value)
    return storage.save(script).model_dump()


@app.delete("/api/scripts/{script_id}")
def delete_script(script_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("script_id") == script_id:
        raise HTTPException(409, "دا سکریپټ اوس روان دی")
    if not storage.delete(script_id):
        raise HTTPException(404, "سکریپټ ونه موندل شو")
    task_store.forget_script(script_id)
    return {"ok": True}


@app.post("/api/scripts/{script_id}/run")
def run_script(script_id: str, payload: RunRequest) -> dict:
    try:
        return manager.start_run(
            script_id,
            variables=payload.variables,
            speed=payload.speed,
            headless=payload.headless,
            keep_open=payload.keep_open,
            browser=payload.browser,
            account_id=payload.account_id,
        )
    except KeyError:
        raise HTTPException(404, "سکریپټ ونه موندل شو") from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None


# ------------------------------------------------------------ accounts


@app.get("/api/accounts")
def list_accounts() -> dict:
    overview = account_store.overview()
    # Two accounts of the same site behind one address is the pattern those
    # sites look for; the page says so rather than letting it pass quietly.
    overview["sharing_proxy"] = account_store.sharing_proxy()
    return overview


@app.get("/api/fingerprints")
def list_fingerprints() -> dict:
    """The hundred browser identities, and how many accounts wear each."""
    used: dict[str, int] = {}
    for account in account_store.accounts():
        if account.fingerprint_id:
            used[account.fingerprint_id] = used.get(account.fingerprint_id, 0) + 1
    return {
        "profiles": [
            profile.summary(used.get(profile.id, 0))
            for profile in fingerprints.all_profiles()
        ],
        "tiers": [
            {"id": tier, "label": fingerprints.TIER_LABEL[tier],
             "note": fingerprints.TIER_NOTE[tier]}
            for tier in (fingerprints.SAFE, fingerprints.FAIR, fingerprints.BOLD)
        ],
    }


@app.post("/api/accounts/{account_id}/fingerprint")
def set_fingerprint(account_id: str, payload: FingerprintAssign) -> dict:
    try:
        account = account_store.set_fingerprint(account_id, payload.fingerprint_id)
    except KeyError:
        raise HTTPException(404, "پېژندګلوي ونه موندل شوه") from None
    if account is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    return account.summary()


@app.post("/api/accounts/login/start")
def account_login_start(payload: LoginStart) -> dict:
    try:
        return manager.start_login(
            payload.category, label=payload.label, browser=payload.browser
        )
    except KeyError:
        raise HTTPException(404, "کټګوري ونه موندل شوه") from None
    except AccountLimitReached as exc:
        raise HTTPException(409, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/accounts/login/finish")
def account_login_finish() -> dict:
    try:
        return manager.finish_login()
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.patch("/api/accounts/{account_id}")
def patch_account(account_id: str, payload: AccountPatch) -> dict:
    account = account_store.update(account_id, label=payload.label)
    if account is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    return account.summary()


@app.delete("/api/accounts/{account_id}")
def delete_account(account_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("account_id") == account_id:
        raise HTTPException(409, "دا اکاونټ اوس کارېږي")
    if not account_store.delete(account_id):
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    task_store.forget_account(account_id)
    return {"ok": True}


@app.patch("/api/accounts/categories/{category_id}")
def patch_category(category_id: str, payload: CategoryPatch) -> dict:
    if payload.max_accounts is None:
        raise HTTPException(400, "max_accounts اړین دی")
    category = account_store.set_limit(category_id, payload.max_accounts)
    if category is None:
        raise HTTPException(404, "کټګوري ونه موندل شوه")
    used = account_store.count(category_id)
    if used > category.max_accounts:
        raise HTTPException(
            400,
            f"اوس مهال {used} اکاونټه شته — حد له دې کم نه شي کېدای.",
        )
    return {**category.model_dump(), "used": used}


# ------------------------------------------------------------------- tasks


# ----------------------------------------------------------------- proxies


@app.get("/api/proxies")
def list_proxies() -> dict:
    assignments = account_store.assignments()
    used = {}
    for proxy_id in assignments.values():
        used[proxy_id] = used.get(proxy_id, 0) + 1
    return {
        "proxies": [p.summary(used.get(p.id, 0)) for p in proxy_store.list()],
        "overview": proxy_store.overview(assignments),
    }


@app.post("/api/proxies")
def import_proxies(payload: ProxyImport) -> dict:
    found, bad = parse_many(payload.text)
    for index, proxy in enumerate(found, start=1):
        if payload.label:
            proxy.label = f"{payload.label} {index}" if len(found) > 1 else payload.label
    added, skipped = proxy_store.add_many(found)
    return {
        "added": [p.summary() for p in added],
        "skipped": skipped,
        "rejected": bad,
    }


@app.patch("/api/proxies/{proxy_id}")
def patch_proxy(proxy_id: str, payload: ProxyPatch) -> dict:
    changes = {
        key: value
        for key, value in payload.model_dump().items()
        if key in payload.model_fields_set
    }
    proxy = proxy_store.update(proxy_id, **changes)
    if proxy is None:
        raise HTTPException(404, "پروکسي ونه موندل شوه")
    return proxy.summary()


@app.delete("/api/proxies/{proxy_id}")
def delete_proxy(proxy_id: str) -> dict:
    if not proxy_store.delete(proxy_id):
        raise HTTPException(404, "پروکسي ونه موندل شوه")
    freed = account_store.forget_proxy(proxy_id)
    return {"ok": True, "accounts_freed": freed}


@app.post("/api/proxies/check")
def check_proxies(payload: ProxyCheck) -> dict:
    try:
        return manager.start_proxy_check(payload.proxy_ids)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/proxies/distribute")
def distribute_proxies(payload: ProxyDistribute) -> dict:
    try:
        return manager.distribute_proxies(payload.account_ids)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None


@app.post("/api/accounts/{account_id}/proxy")
def assign_proxy(account_id: str, payload: ProxyAssign) -> dict:
    if payload.proxy_id and proxy_store.get(payload.proxy_id) is None:
        raise HTTPException(404, "پروکسي ونه موندل شوه")
    account = account_store.set_proxy(account_id, payload.proxy_id, payload.mode)
    if account is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    return account.summary()


# ------------------------------------------------------------------ security


@app.get("/api/security")
def security_state() -> dict:
    return vault.state()


@app.post("/api/security/setup")
def security_setup(payload: VaultSetup) -> dict:
    """First run: choose the password everything else is kept under."""
    try:
        report = vault.setup(
            payload.password,
            use_windows_password=payload.use_windows_password,
            windows_password=payload.windows_password,
            use_biometric=payload.use_biometric,
        )
    except VaultError as exc:
        raise HTTPException(400, str(exc)) from None
    return {**vault.state(), "report": report}


@app.post("/api/security/unlock")
def security_unlock(payload: VaultUnlock) -> dict:
    if not vault.configured:
        raise HTTPException(409, "لا پټنوم نه دی ټاکل شوی.")
    if not vault.unlock(payload.password, payload.method):
        raise HTTPException(401, _wrong(payload.method))
    return vault.state()


@app.post("/api/security/lock")
def security_lock() -> dict:
    vault.lock()
    return vault.state()


@app.post("/api/security/verify")
def security_verify(payload: VaultUnlock) -> dict:
    """Prove it is them again, for one action, without opening anything."""
    if not vault.verify(payload.password, payload.method):
        raise HTTPException(401, _wrong(payload.method))
    return {"ok": True}


@app.post("/api/security/password")
def security_password(payload: VaultPassword) -> dict:
    try:
        vault.change_password(payload.current, payload.new)
    except VaultError as exc:
        raise HTTPException(400, str(exc)) from None
    return vault.state()


@app.post("/api/security/methods")
def security_methods(payload: VaultMethods) -> dict:
    try:
        if payload.windows is not None:
            vault.set_windows_password(payload.windows, payload.windows_password)
        if payload.biometric is not None:
            vault.set_biometric(payload.biometric)
    except Locked as exc:
        raise HTTPException(423, str(exc)) from None
    except VaultError as exc:
        raise HTTPException(400, str(exc)) from None
    return vault.state()


@app.post("/api/security/biometric/enroll")
def security_enroll() -> dict:
    """Windows registers fingerprints, not us — so open its page."""
    from . import winauth

    return {"opened": winauth.open_enrollment(), **vault.state()}


def _wrong(method: str) -> str:
    if method == "windows":
        return "د ویندوز پټنوم سم نه دی."
    if method == "biometric":
        return "د ګوتې نښه ونه پېژندل شوه."
    return "پټنوم سم نه دی."


def _prove(code: str, method: str = "password") -> None:
    """Gate for anything that puts a secret on screen or in a file."""
    if not vault.configured:
        return
    if not vault.verify(code, method):
        raise HTTPException(401, _wrong(method))


# ------------------------------------------------- an account's own details


@app.get("/api/accounts/{account_id}/detail")
def account_detail(account_id: str) -> dict:
    """Everything about one account — and not one secret among it."""
    account = account_store.get(account_id)
    if account is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    category = account_store.category(account.category)
    proxy = proxy_store.get(account.proxy_id) if account.proxy_id else None
    cookies = account_store.load_cookies(account_id)
    return {
        **account.summary(),
        "category_name": getattr(category, "name", account.category),
        "login_url": getattr(category, "login_url", account.login_url),
        "proxy": proxy.summary() if proxy else None,
        "secrets": credential_store.summary(account_id),
        # The names only. What is in them stays behind the password.
        "cookie_names": sorted({str(c.get("name", "")) for c in cookies}),
        "cookie_domains": sorted({str(c.get("domain", "")) for c in cookies}),
    }


@app.post("/api/accounts/{account_id}/cookies/reveal")
def account_cookies_reveal(account_id: str, payload: SecretReveal) -> dict:
    """The cookies themselves. These *are* the login, so they are gated."""
    if account_store.get(account_id) is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    _prove(payload.code, payload.method)
    return {"cookies": account_store.load_cookies(account_id)}


@app.post("/api/accounts/{account_id}/secrets")
def account_secrets_save(account_id: str, payload: SecretSave) -> dict:
    if account_store.get(account_id) is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    _prove(payload.code, payload.method)
    try:
        return credential_store.set(
            account_id,
            username=payload.username,
            password=payload.password,
            note=payload.note,
        )
    except Locked as exc:
        raise HTTPException(423, str(exc)) from None


@app.post("/api/accounts/{account_id}/secrets/reveal")
def account_secrets_reveal(account_id: str, payload: SecretReveal) -> dict:
    if account_store.get(account_id) is None:
        raise HTTPException(404, "اکاونټ ونه موندل شو")
    _prove(payload.code, payload.method)
    try:
        return credential_store.reveal(account_id)
    except Locked as exc:
        raise HTTPException(423, str(exc)) from None


# ------------------------------------------------------------ export/import


@app.post("/api/export/accounts")
def export_accounts(payload: ExportRequest) -> dict:
    _prove(payload.code, payload.method)
    wanted = set(payload.ids or [])
    accounts = [
        a for a in account_store.accounts() if not wanted or a.id in wanted
    ]
    secrets: dict[str, dict[str, str]] = {}
    if payload.include_secrets:
        for account in accounts:
            found = credential_store.reveal(account.id)
            if found.get("username") or found.get("password"):
                secrets[account.id] = found
    cookies: dict[str, list[dict]] = {}
    if payload.include_cookies:
        for account in accounts:
            saved = account_store.load_cookies(account.id)
            if saved:
                cookies[account.id] = saved
    text = exporting.accounts_csv(
        accounts,
        categories={c.id: c.name for c in account_store.categories()},
        proxies={p.id: p for p in proxy_store.list()},
        identities={f.id: f for f in fingerprints.all_profiles()},
        secrets=secrets,
        cookies=cookies,
    )
    return _written("accounts", "csv", text, len(accounts))


@app.post("/api/import/accounts")
def import_accounts(payload: ImportRequest) -> dict:
    _prove(payload.code, payload.method)
    rows, problems = exporting.accounts_from_csv(_text_of(payload))
    by_address = {p.address: p for p in proxy_store.list()}
    added = 0
    with_session = 0
    for row in rows:
        try:
            account = account_store.create(row["category"], row["label"])
        except (KeyError, AccountLimitReached) as exc:
            problems.append(f"«{row['label']}»: {exc}")
            continue
        added += 1
        if row.get("display_name"):
            account_store.update(account.id, display_name=row["display_name"])
        if row.get("fingerprint_id"):
            try:
                account_store.set_fingerprint(account.id, row["fingerprint_id"])
            except KeyError:
                problems.append(f"«{row['label']}»: پېژندګلوي ونه پېژندل شوه")
        proxy = by_address.get(row.get("proxy_address", ""))
        if proxy is not None:
            account_store.set_proxy(account.id, proxy.id, row.get("proxy_mode") or "fixed")
        if row.get("username") or row.get("password"):
            credential_store.set(
                account.id, row.get("username", ""), row.get("password", ""),
                row.get("note", ""),
            )
        if row.get("cookies"):
            # The file carried the session, so the account arrives signed in.
            account_store.save_cookies(account.id, row["cookies"])
            with_session += 1
    return {
        "added": added,
        "problems": problems,
        "note": (
            f"{with_session} اکاونټه له خپلې ناستې سره راغلل."
            if with_session
            else "پدې فایل کې کوکیز نه وو — راوړل شوي اکاونټونه یو ځل ننوتل "
                 "غواړي."
        ),
    }


@app.post("/api/export/proxies")
def export_proxies(payload: ExportRequest) -> dict:
    _prove(payload.code, payload.method)
    wanted = set(payload.ids or [])
    proxies = [p for p in proxy_store.list() if not wanted or p.id in wanted]
    used = {}
    for account in account_store.accounts():
        if account.proxy_id:
            used[account.proxy_id] = used.get(account.proxy_id, 0) + 1
    text = exporting.proxies_csv(
        proxies, used_by=used, with_passwords=payload.include_secrets
    )
    return _written("proxies", "csv", text, len(proxies))


@app.post("/api/import/proxies")
def import_proxies(payload: ImportRequest) -> dict:
    _prove(payload.code, payload.method)
    text = _text_of(payload)
    lines, problems = exporting.proxies_from_csv(text)
    if not lines:
        # Not a CSV, then — the paste box accepts a plain seller list too.
        parsed, bad = parse_many(text)
        problems.extend(bad)
    else:
        parsed, bad = parse_many("\n".join(lines))
        problems.extend(bad)
    added, duplicates = proxy_store.add_many(parsed)
    return {
        "added": len(added),
        "duplicates": duplicates,
        "problems": problems,
    }


@app.post("/api/export/scripts")
def export_scripts(payload: ExportRequest) -> dict:
    _prove(payload.code, payload.method)
    wanted = set(payload.ids or [])
    scripts = [s for s in storage.list() if not wanted or s.id in wanted]
    shape = (payload.format or "json").lower()

    if shape == "csv":
        return _written("scripts", "csv", exporting.scripts_csv(scripts), len(scripts))
    if shape == "json":
        return _written(
            "scripts", "json", exporting.scripts_json(scripts), len(scripts)
        )
    if shape not in {"py", "js"}:
        raise HTTPException(400, "دا بڼه نه پېژندل کېږي.")

    # Code is one file per script: a Python file holding six recordings would
    # be nobody's idea of useful.
    folder = config.BASE_DIR / "exports"
    folder.mkdir(parents=True, exist_ok=True)
    written = []
    for script in scripts:
        body = (
            exporting.script_to_python(script) if shape == "py"
            else exporting.script_to_javascript(script)
        )
        target = folder / f"{_slug(script.name)}-{script.id}.{shape}"
        target.write_text(body, encoding="utf-8")
        written.append(str(target))
    return {
        "folder": str(folder),
        "files": written,
        "count": len(written),
        "format": shape,
    }


@app.post("/api/import/scripts")
def import_scripts(payload: ImportRequest) -> dict:
    _prove(payload.code, payload.method)
    scripts, problems = exporting.scripts_from_json(_text_of(payload))
    added = 0
    for script in scripts:
        # A fresh id, so importing the same file twice does not overwrite
        # what is already here.
        script.id = new_id("scr")
        storage.save(script)
        added += 1
    return {"added": added, "problems": problems}


def _slug(name: str) -> str:
    keep = [c if c.isalnum() or c in "-_" else "-" for c in (name or "script")]
    return ("".join(keep).strip("-") or "script")[:40]


def _written(kind: str, extension: str, text: str, count: int) -> dict:
    folder = config.BASE_DIR / "exports"
    folder.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = folder / f"{kind}-{stamp}.{extension}"
    target.write_text(text, encoding="utf-8")
    return {
        "folder": str(folder),
        "files": [str(target)],
        "count": count,
        "format": extension,
    }


def _text_of(payload: ImportRequest) -> str:
    if payload.text.strip():
        return payload.text
    if payload.path.strip():
        source = Path(payload.path.strip().strip('"'))
        if not source.exists():
            raise HTTPException(404, f"فایل ونه موندل شو: {source}")
        try:
            return source.read_text("utf-8-sig")
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(400, f"فایل ونه لوستل شو: {exc}") from None
    raise HTTPException(400, "هېڅ معلومات رانغلل.")


@app.get("/api/system")
def system_info(windows: int = 1, headless: bool = False) -> dict:
    """What the machine is, and what N browser windows would cost on it."""
    return {
        "machine": machine().to_dict(),
        "estimate": estimate(windows, headless),
        # A proxy set for the whole machine (VPN, antivirus web shield,
        # company network) is inherited by every browser we open — the usual
        # reason a page fails here while it opens by hand.
        "system_proxy": netcheck.system_proxy(),
    }


@app.post("/api/accounts/check")
def check_accounts(payload: CookieCheck) -> dict:
    try:
        return manager.start_cookie_check(payload.account_ids)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.get("/api/tasks/{task_id}/log")
def task_log(task_id: str, limit: int = 300) -> dict:
    if task_store.get(task_id) is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return {"entries": task_store.read_log(task_id, limit=limit)}


@app.delete("/api/tasks/{task_id}/log")
def clear_task_log(task_id: str) -> dict:
    task_store.clear_log(task_id)
    return {"ok": True}


@app.get("/api/tasks")
def list_tasks() -> dict:
    return {
        "tasks": [t.summary() for t in task_store.list()],
        "overview": task_store.overview(),
    }


@app.post("/api/tasks")
def create_task(payload: TaskUpsert) -> dict:
    fields = {k: v for k, v in payload.model_dump().items() if v is not None}
    return task_store.create(**fields).summary()


@app.get("/api/tasks/{task_id}")
def get_task(task_id: str) -> dict:
    task = task_store.get(task_id)
    if task is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return task.summary()


@app.patch("/api/tasks/{task_id}")
def patch_task(task_id: str, payload: TaskUpsert) -> dict:
    changes = {
        key: value
        for key, value in payload.model_dump().items()
        if key in payload.model_fields_set
    }
    task = task_store.update(task_id, **changes)
    if task is None:
        raise HTTPException(404, "کار ونه موندل شو")
    return task.summary()


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: str) -> dict:
    if manager.state != "idle" and manager.detail.get("task_id") == task_id:
        raise HTTPException(409, "دا کار اوس روان دی")
    if not task_store.delete(task_id):
        raise HTTPException(404, "کار ونه موندل شو")
    return {"ok": True}


@app.post("/api/tasks/{task_id}/run")
def run_task(task_id: str, payload: TaskRun) -> dict:
    try:
        return manager.start_task(task_id, resume=payload.resume)
    except KeyError:
        raise HTTPException(404, "کار ونه موندل شو") from None
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/record/start")
def record_start(payload: RecordStart) -> dict:
    try:
        return manager.start_recording(
            name=payload.name,
            url=payload.url,
            capture_scroll=payload.capture_scroll,
            script_id=payload.script_id,
            browser=payload.browser,
            account_id=payload.account_id,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from None
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/record/stop")
def record_stop() -> dict:
    try:
        return manager.stop_recording()
    except SessionBusy as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/session/stop")
def session_stop() -> dict:
    return manager.stop()


@app.get("/api/session")
def session_status() -> dict:
    return manager.status()


@app.get("/api/events")
def events(limit: int = 200) -> list[dict]:
    return manager.bus.history(limit)


@app.post("/api/shutdown")
def shutdown() -> dict:
    """Stop the browser and end the process.

    The app calls this as its window closes. Without it the backend would keep
    running with no window anywhere — invisible, holding its own file open.
    """
    manager.shutdown()
    threading.Timer(0.25, exit_now).start()
    return {"ok": True}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=1000)

    def on_event(event: dict) -> None:
        # Called from the worker thread: hop back onto the event loop.
        loop.call_soon_threadsafe(_offer, queue, event)

    unsubscribe = manager.bus.subscribe(on_event)
    lifetime.client_connected()
    try:
        for past in manager.bus.history(50):
            await websocket.send_json(past)
        while True:
            event = await queue.get()
            await websocket.send_json(event)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        unsubscribe()
        lifetime.client_gone()


def _offer(queue: asyncio.Queue, event: dict) -> None:
    try:
        queue.put_nowait(event)
    except asyncio.QueueFull:
        pass


def attach_log_streams() -> None:
    """Give the process somewhere to write when there is no console.

    A PyInstaller *windowed* build has no console at all: sys.stdout and
    sys.stderr are None, and uvicorn's very first log line would raise. Point
    them at a file under the app directory instead, which also gives the user
    something to send when something goes wrong.
    """
    import sys

    if sys.stdout is not None and sys.stderr is not None:
        return
    config.ensure_dirs()
    handle = open(  # noqa: SIM115 - lives for the process lifetime
        config.LOGS_DIR / "backend.log", "a", encoding="utf-8", buffering=1
    )
    if sys.stdout is None:
        sys.stdout = handle
    if sys.stderr is None:
        sys.stderr = handle


def main(argv: list[str] | None = None) -> None:
    import argparse
    import os
    import uvicorn

    parser = argparse.ArgumentParser(description="WebScripts backend")
    parser.add_argument(
        "--parent-pid",
        type=int,
        default=int(os.environ.get("WEBSCRIPTS_PARENT_PID") or 0),
        help="exit as soon as this process (the desktop app) is gone",
    )
    parser.add_argument("--host", default=config.HOST)
    parser.add_argument("--port", type=int, default=config.PORT)
    args = parser.parse_args(argv)

    config.ensure_dirs()
    attach_log_streams()

    global lifetime
    lifetime = Lifetime(shutdown=_shutdown_and_exit, parent_pid=args.parent_pid)
    lifetime.busy = lambda: manager.state != "idle"
    lifetime.start()

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


def _shutdown_and_exit() -> None:
    print(f"webscripts: shutting down — {lifetime.reason}")
    manager.shutdown()
    exit_now()


if __name__ == "__main__":
    main()
