"""API tests — the browser is never started because no run is requested."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from webscripts import browsers, server
from webscripts.accounts import AccountStore
from webscripts.settings import SettingsStore
from webscripts.storage import Storage


@pytest.fixture()
def client(tmp_path, monkeypatch):
    storage = Storage(tmp_path)
    settings = SettingsStore(tmp_path / "settings.json")
    accounts = AccountStore(tmp_path / "accounts.json")
    monkeypatch.setattr(server, "storage", storage)
    monkeypatch.setattr(server, "settings_store", settings)
    monkeypatch.setattr(server, "account_store", accounts)
    monkeypatch.setattr(server.manager, "storage", storage)
    monkeypatch.setattr(server.manager, "settings", settings)
    monkeypatch.setattr(server.manager, "accounts", accounts)
    return TestClient(server.app)


def test_health(client):
    body = client.get("/api/health").json()
    assert body["ok"] is True
    assert body["state"] == "idle"


def test_script_crud(client):
    created = client.post(
        "/api/scripts", json={"name": "تم بدلول", "start_url": "https://facebook.com"}
    ).json()
    script_id = created["id"]

    assert client.get(f"/api/scripts/{script_id}").json()["name"] == "تم بدلول"

    updated = client.put(
        f"/api/scripts/{script_id}",
        json={
            "name": "نوی نوم",
            "steps": [{"action": "goto", "url": "https://x.test"}],
        },
    ).json()
    assert updated["name"] == "نوی نوم"
    assert len(updated["steps"]) == 1

    listing = client.get("/api/scripts").json()
    assert listing[0]["step_count"] == 1

    assert client.delete(f"/api/scripts/{script_id}").json()["ok"] is True
    assert client.get(f"/api/scripts/{script_id}").status_code == 404


def test_run_unknown_script_is_404(client):
    assert client.post("/api/scripts/scr_missing/run", json={}).status_code == 404


def test_run_requires_secret_variables(client):
    created = client.post("/api/scripts", json={"name": "لاګ ان"}).json()
    client.put(
        f"/api/scripts/{created['id']}",
        json={
            "steps": [{"action": "type", "value": "{{password}}", "secret": True}],
            "variables": [{"name": "password", "secret": True}],
        },
    )

    response = client.post(f"/api/scripts/{created['id']}/run", json={"variables": {}})

    assert response.status_code == 400
    assert "password" in response.json()["detail"]


def test_stop_recording_when_idle_is_409(client):
    assert client.post("/api/record/stop").status_code == 409


def test_events_history(client):
    server.manager.log("info", "سلام")
    body = client.get("/api/events?limit=10").json()
    assert body[-1]["message"] == "سلام"


def test_settings_roundtrip(client):
    defaults = client.get("/api/settings").json()
    assert defaults["browser"] == "auto"

    updated = client.put("/api/settings", json={"browser": "chrome", "speed": 2.0}).json()
    assert updated["browser"] == "chrome"
    assert updated["speed"] == 2.0
    assert client.get("/api/settings").json()["browser"] == "chrome"

    assert client.post("/api/settings/reset").json()["browser"] == "auto"


def test_invalid_setting_is_rejected(client):
    response = client.put("/api/settings", json={"speed": 500})

    assert response.status_code == 400
    assert client.get("/api/settings").json()["speed"] == 1.0


def test_browsers_endpoint_lists_the_catalog(client):
    body = client.get("/api/browsers").json()

    ids = {b["id"] for b in body["browsers"]}
    assert "edge" in ids and "chrome" in ids
    assert body["selected"] == "auto"
    assert all("installed" in b for b in body["browsers"])


def test_health_reports_the_browser(client, monkeypatch):
    from webscripts.browsers import BrowserInfo

    monkeypatch.setattr(
        browsers,
        "resolve",
        lambda preferred="auto": BrowserInfo(
            id="edge", name="Microsoft Edge", family="chromium",
            path="C:/edge.exe", installed=True,
        ),
    )

    body = client.get("/api/health").json()

    assert body["browser"]["id"] == "edge"
    assert body["browser"]["installed"] is True


# ------------------------------------------------------------------ accounts


def test_accounts_overview_lists_categories(client):
    body = client.get("/api/accounts").json()

    ids = {c["id"] for c in body["categories"]}
    assert {"facebook", "x", "instagram", "google"} <= ids
    assert body["accounts"] == []
    facebook = next(c for c in body["categories"] if c["id"] == "facebook")
    assert facebook["max_accounts"] == 2
    assert facebook["used"] == 0


def test_category_limit_can_be_changed(client):
    body = client.patch(
        "/api/accounts/categories/instagram", json={"max_accounts": 4}
    ).json()

    assert body["max_accounts"] == 4
    listed = client.get("/api/accounts").json()["categories"]
    assert next(c for c in listed if c["id"] == "instagram")["max_accounts"] == 4


def test_unknown_category_is_404(client):
    response = client.patch(
        "/api/accounts/categories/myspace", json={"max_accounts": 2}
    )
    assert response.status_code == 404


def test_rename_and_delete_account(client, tmp_path):
    account = server.account_store.create("facebook", "کاري")
    server.account_store.save_cookies(account.id, [{"name": "c_user"}])

    renamed = client.patch(
        f"/api/accounts/{account.id}", json={"label": "شخصي"}
    ).json()
    assert renamed["label"] == "شخصي"

    assert client.delete(f"/api/accounts/{account.id}").json()["ok"] is True
    assert client.get("/api/accounts").json()["accounts"] == []


def test_delete_unknown_account_is_404(client):
    assert client.delete("/api/accounts/acc_missing").status_code == 404


def test_login_start_refuses_when_the_category_is_full(client):
    account = server.account_store.create("instagram")
    server.account_store.save_cookies(account.id, [{"name": "sessionid"}])

    response = client.post(
        "/api/accounts/login/start", json={"category": "instagram"}
    )

    assert response.status_code == 409
    assert "انسټاګرام" in response.json()["detail"]


def test_login_finish_when_idle_is_409(client):
    assert client.post("/api/accounts/login/finish").status_code == 409


def test_run_with_an_unknown_account_is_400(client):
    created = client.post("/api/scripts", json={"name": "x"}).json()

    response = client.post(
        f"/api/scripts/{created['id']}/run", json={"account_id": "acc_nope"}
    )

    assert response.status_code == 400
    assert "اکاونټ" in response.json()["detail"]


def test_log_streams_are_attached_when_there_is_no_console(tmp_path, monkeypatch):
    """A windowed PyInstaller build has sys.stdout/stderr set to None."""
    import sys

    from webscripts import config

    monkeypatch.setattr(config, "BASE_DIR", tmp_path)
    monkeypatch.setattr(config, "SCRIPTS_DIR", tmp_path / "scripts")
    monkeypatch.setattr(config, "LOGS_DIR", tmp_path / "logs")
    monkeypatch.setattr(config, "SHOTS_DIR", tmp_path / "shots")
    monkeypatch.setattr(config, "PROFILE_DIR", tmp_path / "profile")
    monkeypatch.setattr(config, "ACCOUNTS_DIR", tmp_path / "accounts")
    monkeypatch.setattr(sys, "stdout", None)
    monkeypatch.setattr(sys, "stderr", None)

    server.attach_log_streams()

    try:
        assert sys.stdout is not None and sys.stderr is not None
        print("hello from a windowed build")
        assert (tmp_path / "logs" / "backend.log").exists()
    finally:
        sys.stdout.close()


def test_log_streams_are_left_alone_when_a_console_exists():
    import sys

    before = sys.stdout
    server.attach_log_streams()
    assert sys.stdout is before
