"""API tests — the browser is never started because no run is requested."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from webscripts import browsers, server
from webscripts.settings import SettingsStore
from webscripts.storage import Storage


@pytest.fixture()
def client(tmp_path, monkeypatch):
    storage = Storage(tmp_path)
    settings = SettingsStore(tmp_path / "settings.json")
    monkeypatch.setattr(server, "storage", storage)
    monkeypatch.setattr(server, "settings_store", settings)
    monkeypatch.setattr(server.manager, "storage", storage)
    monkeypatch.setattr(server.manager, "settings", settings)
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
