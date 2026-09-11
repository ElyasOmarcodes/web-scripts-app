"""API tests — the browser is never started because no run is requested."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from webscripts import browsers, server
from webscripts.accounts import AccountStore
from webscripts.settings import SettingsStore
from webscripts.storage import Storage
from webscripts.proxies import ProxyStore
from webscripts.tasks import TaskStore


@pytest.fixture()
def client(tmp_path, monkeypatch):
    storage = Storage(tmp_path)
    settings = SettingsStore(tmp_path / "settings.json")
    accounts = AccountStore(tmp_path / "accounts.json")
    tasks = TaskStore(tmp_path / "tasks.json")
    proxies = ProxyStore(tmp_path / "proxies.json")
    monkeypatch.setattr(server, "task_store", tasks)
    monkeypatch.setattr(server.manager, "tasks", tasks)
    monkeypatch.setattr(server, "proxy_store", proxies)
    monkeypatch.setattr(server.manager, "proxies", proxies)
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


# ------------------------------------------------------------------- tasks


def make_script(client, steps=1):
    script = client.post("/api/scripts", json={"name": "سکریپټ"}).json()
    client.put(
        f"/api/scripts/{script['id']}",
        json={
            "steps": [
                {
                    "id": f"stp_{i}",
                    "action": "click",
                    "targets": [{"type": "css", "value": "#a", "kind": "test"}],
                }
                for i in range(steps)
            ]
        },
    )
    return script["id"]


def test_task_crud(client):
    script_id = make_script(client)
    created = client.post(
        "/api/tasks",
        json={"name": "د ایکس پوستونه", "script_id": script_id,
              "account_ids": ["a1", "a2"], "concurrency": 2},
    ).json()

    assert created["name"] == "د ایکس پوستونه"
    assert created["pending_count"] == 2
    assert created["status"] == "draft"

    listed = client.get("/api/tasks").json()
    assert [t["id"] for t in listed["tasks"]] == [created["id"]]
    assert listed["overview"]["total"] == 1

    patched = client.patch(
        f"/api/tasks/{created['id']}", json={"name": "نوی نوم", "concurrency": 3}
    ).json()
    assert (patched["name"], patched["concurrency"]) == ("نوی نوم", 3)

    assert client.delete(f"/api/tasks/{created['id']}").status_code == 200
    assert client.get("/api/tasks").json()["tasks"] == []


def test_a_task_without_a_script_cannot_run(client):
    task = client.post("/api/tasks", json={"account_ids": ["a1"]}).json()

    answer = client.post(f"/api/tasks/{task['id']}/run", json={})

    assert answer.status_code == 400
    assert "سکریپټ" in answer.json()["detail"]


def test_a_task_without_accounts_cannot_run(client):
    script_id = make_script(client)
    task = client.post("/api/tasks", json={"script_id": script_id}).json()

    answer = client.post(f"/api/tasks/{task['id']}/run", json={})

    assert answer.status_code == 400
    assert "اکاونټ" in answer.json()["detail"]


def test_an_impossible_concurrency_is_rejected(client):
    """The machine decides what is sensible; the API only rejects nonsense."""
    assert client.post("/api/tasks", json={"concurrency": 0}).status_code == 422
    assert client.post("/api/tasks", json={"concurrency": 99}).status_code == 422


def test_deleting_a_script_leaves_its_tasks_without_one(client):
    script_id = make_script(client)
    task = client.post("/api/tasks", json={"script_id": script_id}).json()

    client.delete(f"/api/scripts/{script_id}")

    assert client.get(f"/api/tasks/{task['id']}").json()["script_id"] == ""


def test_a_missing_task_is_a_404(client):
    assert client.get("/api/tasks/tsk_nope").status_code == 404
    assert client.post("/api/tasks/tsk_nope/run", json={}).status_code == 404


def test_system_info_reports_the_machine_and_an_estimate(client):
    body = client.get("/api/system?windows=3").json()

    assert body["machine"]["cores"] >= 1
    assert body["estimate"]["windows"] == 3
    assert body["estimate"]["cores_needed"] > 0
    assert body["estimate"]["level"] in {"easy", "busy", "over"}


def test_headless_is_cheaper_than_a_visible_window(client):
    visible = client.get("/api/system?windows=4").json()["estimate"]
    hidden = client.get("/api/system?windows=4&headless=true").json()["estimate"]

    assert hidden["cores_needed"] < visible["cores_needed"]
    assert hidden["ram_needed_mb"] < visible["ram_needed_mb"]


def test_a_task_keeps_a_log_of_its_own(client):
    script_id = make_script(client)
    task = client.post(
        "/api/tasks", json={"script_id": script_id, "account_ids": ["a1"]}
    ).json()

    assert client.get(f"/api/tasks/{task['id']}/log").json()["entries"] == []
    assert client.get("/api/tasks/tsk_nope/log").status_code == 404


def test_a_task_can_run_on_more_than_four_accounts_at_once(client):
    created = client.post("/api/tasks", json={"concurrency": 8}).json()

    assert created["concurrency"] == 8


def test_checking_cookies_needs_an_account(client):
    answer = client.post("/api/accounts/check", json={"account_ids": ["nope"]})

    assert answer.status_code == 400


def test_a_script_can_carry_its_own_pacing(client):
    script_id = make_script(client)

    updated = client.put(
        f"/api/scripts/{script_id}",
        json={"gap_min_ms": 800, "gap_max_ms": 2500},
    ).json()

    assert (updated["gap_min_ms"], updated["gap_max_ms"]) == (800, 2500)

    # Sending null puts it back on the app-wide setting.
    cleared = client.put(
        f"/api/scripts/{script_id}",
        json={"gap_min_ms": None, "gap_max_ms": None},
    ).json()

    assert cleared["gap_min_ms"] is None


# ----------------------------------------------------------------- proxies


def test_importing_a_pasted_list(client):
    answer = client.post(
        "/api/proxies",
        json={"text": "1.2.3.4:8080:user:pw\nnot a proxy\n5.6.7.8:9090"},
    ).json()

    assert len(answer["added"]) == 2
    assert answer["rejected"] == ["not a proxy"]
    # The password stays on this machine.
    assert all("password" not in p for p in answer["added"])

    listing = client.get("/api/proxies").json()
    assert listing["overview"]["total"] == 2
    assert listing["overview"]["unknown"] == 2


def test_the_same_proxy_is_not_imported_twice(client):
    client.post("/api/proxies", json={"text": "1.2.3.4:8080"})

    again = client.post("/api/proxies", json={"text": "1.2.3.4:8080"}).json()

    assert again["added"] == []
    assert again["skipped"] == 1


def test_assigning_a_proxy_to_an_account(client):
    proxy = client.post("/api/proxies", json={"text": "1.2.3.4:8080"}).json()
    proxy_id = proxy["added"][0]["id"]
    # Made directly: the login flow would open a real browser.
    account_id = server.account_store.create("facebook", "ټیسټ").id

    answer = client.post(
        f"/api/accounts/{account_id}/proxy", json={"proxy_id": proxy_id}
    ).json()

    assert answer["proxy_id"] == proxy_id
    assert answer["proxy_mode"] == "fixed"
    assert client.get("/api/proxies").json()["proxies"][0]["used_by"] == 1


def test_an_unknown_proxy_cannot_be_assigned(client):
    account_id = server.account_store.create("facebook", "ټیسټ").id

    answer = client.post(
        f"/api/accounts/{account_id}/proxy", json={"proxy_id": "prx_nope"}
    )

    assert answer.status_code == 404


def test_deleting_a_proxy_frees_the_accounts_using_it(client):
    proxy_id = client.post(
        "/api/proxies", json={"text": "1.2.3.4:8080"}
    ).json()["added"][0]["id"]
    account_id = server.account_store.create("facebook", "ټیسټ").id
    client.post(f"/api/accounts/{account_id}/proxy", json={"proxy_id": proxy_id})

    answer = client.delete(f"/api/proxies/{proxy_id}").json()

    assert answer["accounts_freed"] == 1
    assert server.account_store.get(account_id).proxy_mode == "none"


def test_distributing_gives_each_account_its_own(client):
    client.post("/api/proxies", json={"text": "1.1.1.1:1\n2.2.2.2:2\n3.3.3.3:3"})
    for index in range(3):
        server.account_store.create("x", f"اکاونټ {index}")

    answer = client.post("/api/proxies/distribute", json={}).json()

    assert answer["assigned"] == 3
    assert answer["shared"] == 0
    assigned = {a.proxy_id for a in server.account_store.accounts()}
    assert len(assigned) == 3


def test_distributing_says_when_proxies_have_to_be_shared(client):
    client.post("/api/proxies", json={"text": "1.1.1.1:1"})
    for index in range(3):
        server.account_store.create("x", f"اکاونټ {index}")

    answer = client.post("/api/proxies/distribute", json={}).json()

    assert answer["shared"] == 2


def test_distributing_without_proxies_says_so(client):
    server.account_store.create("x", "یو")

    answer = client.post("/api/proxies/distribute", json={})

    assert answer.status_code == 400


def test_checking_needs_a_proxy_that_exists(client):
    assert client.post(
        "/api/proxies/check", json={"proxy_ids": ["prx_nope"]}
    ).status_code == 400
