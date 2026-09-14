"""The lock as the app actually meets it: over the API."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from webscripts import config, server
from webscripts.accounts import AccountStore
from webscripts.credentials import CredentialStore
from webscripts.proxies import ProxyStore, parse_many
from webscripts.settings import SettingsStore
from webscripts.storage import Storage
from webscripts.tasks import TaskStore
from webscripts.vault import Vault


@pytest.fixture()
def client(tmp_path, monkeypatch):
    vault = Vault(tmp_path / "security.json")
    accounts = AccountStore(tmp_path / "accounts.json")
    # Its own folder: Storage reads every *.json it finds.
    storage = Storage(tmp_path / "scripts")
    proxies = ProxyStore(tmp_path / "proxies.json")
    monkeypatch.setattr(server, "vault", vault)
    monkeypatch.setattr(
        server, "credential_store", CredentialStore(vault, tmp_path / "cred.json")
    )
    monkeypatch.setattr(server, "account_store", accounts)
    monkeypatch.setattr(server, "storage", storage)
    monkeypatch.setattr(server, "proxy_store", proxies)
    monkeypatch.setattr(server, "settings_store", SettingsStore(tmp_path / "s.json"))
    monkeypatch.setattr(server, "task_store", TaskStore(tmp_path / "t.json"))
    monkeypatch.setattr(server.manager, "accounts", accounts)
    monkeypatch.setattr(server.manager, "storage", storage)
    monkeypatch.setattr(server.manager, "proxies", proxies)
    monkeypatch.setattr(config, "BASE_DIR", tmp_path)
    return TestClient(server.app)


def setup_lock(client, password="hunter2"):
    return client.post("/api/security/setup", json={"password": password})


# --------------------------------------------------------------- first run


def test_a_fresh_app_reports_no_password_yet(client):
    body = client.get("/api/security").json()
    assert body["configured"] is False
    assert body["locked"] is False


def test_the_rest_of_the_app_still_answers_before_a_password_is_set(client):
    # Otherwise the first run would be a locked door with no key cut yet.
    assert client.get("/api/accounts").status_code == 200


def test_setting_the_password_leaves_the_app_open(client):
    body = setup_lock(client).json()
    assert body["configured"] is True
    assert body["locked"] is False


def test_a_short_password_is_refused_with_a_reason(client):
    response = client.post("/api/security/setup", json={"password": "abc"})
    assert response.status_code == 400
    assert "تورې" in response.json()["detail"]


def test_a_password_cannot_be_set_twice(client):
    setup_lock(client)
    assert client.post(
        "/api/security/setup", json={"password": "another"}
    ).status_code == 400


# ------------------------------------------------------------- locked door


def test_a_locked_app_answers_nothing_but_the_lock_screen(client):
    setup_lock(client)
    client.post("/api/security/lock")

    assert client.get("/api/accounts").status_code == 423
    assert client.get("/api/scripts").status_code == 423
    assert client.get("/api/proxies").status_code == 423
    # …and the three that must keep working.
    assert client.get("/api/health").status_code == 200
    assert client.get("/api/security").status_code == 200


def test_the_right_password_opens_it_again(client):
    setup_lock(client)
    client.post("/api/security/lock")
    assert client.post(
        "/api/security/unlock", json={"password": "nope"}
    ).status_code == 401
    assert client.get("/api/accounts").status_code == 423

    assert client.post(
        "/api/security/unlock", json={"password": "hunter2"}
    ).status_code == 200
    assert client.get("/api/accounts").status_code == 200


def test_windows_and_fingerprint_are_refused_where_they_do_not_exist(client):
    setup_lock(client)
    assert client.post(
        "/api/security/methods", json={"windows": True, "windows_password": "x"}
    ).status_code == 400
    assert client.post(
        "/api/security/methods", json={"biometric": True}
    ).status_code == 400


def test_changing_the_password(client):
    setup_lock(client)
    assert client.post(
        "/api/security/password", json={"current": "wrong", "new": "longenough"}
    ).status_code == 400
    assert client.post(
        "/api/security/password", json={"current": "hunter2", "new": "longenough"}
    ).status_code == 200
    client.post("/api/security/lock")
    assert client.post(
        "/api/security/unlock", json={"password": "longenough"}
    ).status_code == 200


# ------------------------------------------------------- an account's page


def test_the_detail_page_shows_the_cookie_names_but_not_the_cookies(client):
    account = server.account_store.create("facebook")
    server.account_store.save_cookies(account.id, [
        {"name": "c_user", "value": "100012345", "domain": ".facebook.com"},
        {"name": "xs", "value": "secret-token", "domain": ".facebook.com"},
    ])
    body = client.get(f"/api/accounts/{account.id}/detail").json()
    assert body["cookie_names"] == ["c_user", "xs"]
    assert "secret-token" not in str(body)


def test_cookies_are_shown_only_after_the_password(client):
    setup_lock(client)
    account = server.account_store.create("facebook")
    server.account_store.save_cookies(
        account.id, [{"name": "xs", "value": "secret-token"}]
    )
    refused = client.post(
        f"/api/accounts/{account.id}/cookies/reveal", json={"code": "nope"}
    )
    assert refused.status_code == 401

    allowed = client.post(
        f"/api/accounts/{account.id}/cookies/reveal", json={"code": "hunter2"}
    )
    assert allowed.json()["cookies"][0]["value"] == "secret-token"


def test_an_account_keeps_its_own_username_and_password(client):
    setup_lock(client)
    account = server.account_store.create("facebook")
    saved = client.post(
        f"/api/accounts/{account.id}/secrets",
        json={"code": "hunter2", "username": "elyas", "password": "s3cret"},
    ).json()
    assert saved["has_password"] is True

    detail = client.get(f"/api/accounts/{account.id}/detail").json()
    assert detail["secrets"]["has_password"] is True
    assert "s3cret" not in str(detail)

    assert client.post(
        f"/api/accounts/{account.id}/secrets/reveal", json={"code": "nope"}
    ).status_code == 401
    shown = client.post(
        f"/api/accounts/{account.id}/secrets/reveal", json={"code": "hunter2"}
    ).json()
    assert shown == {"username": "elyas", "password": "s3cret", "note": ""}


# ---------------------------------------------------------- export/import


def test_exporting_accounts_needs_the_password(client, tmp_path):
    setup_lock(client)
    server.account_store.create("facebook", "کاري")
    assert client.post(
        "/api/export/accounts", json={"code": "nope"}
    ).status_code == 401

    body = client.post("/api/export/accounts", json={"code": "hunter2"}).json()
    assert body["count"] == 1
    written = (tmp_path / "exports")
    assert written.exists() and list(written.glob("accounts-*.csv"))


def test_an_export_leaves_passwords_out_unless_asked(client):
    setup_lock(client)
    account = server.account_store.create("facebook", "کاري")
    client.post(
        f"/api/accounts/{account.id}/secrets",
        json={"code": "hunter2", "username": "elyas", "password": "s3cret"},
    )
    plain = client.post("/api/export/accounts", json={"code": "hunter2"}).json()
    assert "s3cret" not in open(plain["files"][0], encoding="utf-8").read()

    full = client.post(
        "/api/export/accounts",
        json={"code": "hunter2", "include_secrets": True},
    ).json()
    assert "s3cret" in open(full["files"][0], encoding="utf-8").read()


def test_only_the_chosen_accounts_are_exported(client):
    setup_lock(client)
    first = server.account_store.create("facebook", "یو")
    server.account_store.create("facebook", "دوه")
    body = client.post(
        "/api/export/accounts", json={"code": "hunter2", "ids": [first.id]}
    ).json()
    assert body["count"] == 1


def test_accounts_come_back_in(client):
    setup_lock(client)
    server.account_store.create("facebook", "کاري")
    exported = client.post("/api/export/accounts", json={"code": "hunter2"}).json()
    text = open(exported["files"][0], encoding="utf-8").read()

    server.account_store.delete(server.account_store.accounts()[0].id)
    body = client.post(
        "/api/import/accounts", json={"code": "hunter2", "text": text}
    ).json()
    assert body["added"] == 1
    assert server.account_store.accounts()[0].label == "کاري"
    assert "کوکیز" in body["note"]


def test_proxies_go_out_and_come_back(client):
    setup_lock(client)
    parsed, _ = parse_many("203.0.113.11:6754:demo:demo\n")
    server.proxy_store.add_many(parsed)
    exported = client.post(
        "/api/export/proxies",
        json={"code": "hunter2", "include_secrets": True},
    ).json()
    text = open(exported["files"][0], encoding="utf-8").read()

    server.proxy_store.delete(server.proxy_store.list()[0].id)
    body = client.post(
        "/api/import/proxies", json={"code": "hunter2", "text": text}
    ).json()
    assert body["added"] == 1
    assert server.proxy_store.list()[0].address == "203.0.113.11:6754"


def test_a_plain_seller_list_still_imports(client):
    setup_lock(client)
    body = client.post(
        "/api/import/proxies",
        json={"code": "hunter2", "text": "203.0.113.9:8080:u:p"},
    ).json()
    assert body["added"] == 1


def test_scripts_export_as_json_and_import_back(client):
    setup_lock(client)
    created = client.post("/api/scripts", json={"name": "تم بدلول"}).json()
    exported = client.post(
        "/api/export/scripts", json={"code": "hunter2", "format": "json"}
    ).json()
    text = open(exported["files"][0], encoding="utf-8").read()

    body = client.post(
        "/api/import/scripts", json={"code": "hunter2", "text": text}
    ).json()
    assert body["added"] == 1
    names = [s["name"] for s in client.get("/api/scripts").json()]
    assert names.count("تم بدلول") == 2
    # A fresh id, so an import never overwrites what is already saved.
    ids = {s["id"] for s in client.get("/api/scripts").json()}
    assert created["id"] in ids and len(ids) == 2


def test_scripts_export_as_code_one_file_each(client):
    setup_lock(client)
    client.post("/api/scripts", json={"name": "یو"})
    client.post("/api/scripts", json={"name": "دوه"})
    body = client.post(
        "/api/export/scripts", json={"code": "hunter2", "format": "py"}
    ).json()
    assert body["count"] == 2
    assert all(name.endswith(".py") for name in body["files"])
    assert "import selenium" in open(body["files"][0], encoding="utf-8").read() \
        or "from selenium" in open(body["files"][0], encoding="utf-8").read()


def test_an_unknown_export_format_is_refused(client):
    setup_lock(client)
    assert client.post(
        "/api/export/scripts", json={"code": "hunter2", "format": "docx"}
    ).status_code == 400


def test_importing_from_a_file_path(client, tmp_path):
    setup_lock(client)
    source = tmp_path / "proxies.txt"
    source.write_text("203.0.113.5:9000\n", encoding="utf-8")
    body = client.post(
        "/api/import/proxies", json={"code": "hunter2", "path": str(source)}
    ).json()
    assert body["added"] == 1


def test_a_missing_file_says_so(client, tmp_path):
    setup_lock(client)
    response = client.post(
        "/api/import/proxies",
        json={"code": "hunter2", "path": str(tmp_path / "nope.csv")},
    )
    assert response.status_code == 404
