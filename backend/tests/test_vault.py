"""The lock: one key, several doors, and nothing readable without one."""

from __future__ import annotations

import json

import pytest

from webscripts.credentials import CredentialStore
from webscripts.vault import Locked, Vault, VaultError


@pytest.fixture()
def vault(tmp_path):
    return Vault(tmp_path / "security.json")


def test_a_fresh_install_has_no_lock(vault):
    assert vault.configured is False
    # Nothing to unlock means nothing is locked — the app opens to its setup
    # page rather than to a password box with no password behind it.
    assert vault.locked is False


def test_setting_a_password_locks_the_app(vault):
    vault.setup("hunter2")
    assert vault.configured is True
    assert vault.locked is False  # setting it up leaves it open
    vault.lock()
    assert vault.locked is True


def test_the_password_itself_is_never_written_down(vault, tmp_path):
    vault.setup("correct horse battery")
    raw = (tmp_path / "security.json").read_text("utf-8")
    assert "correct horse battery" not in raw
    stored = json.loads(raw)
    assert set(stored["wrappers"]) == {"password"}
    assert "salt" in stored["wrappers"]["password"]


def test_the_file_is_readable_by_nobody_else(vault, tmp_path):
    vault.setup("hunter2")
    mode = (tmp_path / "security.json").stat().st_mode & 0o777
    assert mode == 0o600


def test_only_the_right_password_opens_it(vault):
    vault.setup("hunter2")
    vault.lock()
    assert vault.unlock("hunter") is False
    assert vault.locked is True
    assert vault.unlock("hunter2") is True
    assert vault.locked is False


def test_a_short_password_is_refused(vault):
    with pytest.raises(VaultError):
        vault.setup("abc")


def test_secrets_survive_a_password_change(vault):
    vault.setup("hunter2")
    sealed = vault.encrypt_json({"password": "s3cret"})
    vault.change_password("hunter2", "a-longer-one")
    vault.lock()
    assert vault.unlock("hunter2") is False
    assert vault.unlock("a-longer-one") is True
    assert vault.decrypt_json(sealed) == {"password": "s3cret"}


def test_the_old_password_cannot_change_it_twice(vault):
    vault.setup("hunter2")
    vault.change_password("hunter2", "a-longer-one")
    with pytest.raises(VaultError):
        vault.change_password("hunter2", "another-one")


def test_nothing_can_be_read_while_locked(vault):
    vault.setup("hunter2")
    sealed = vault.encrypt_json({"a": 1})
    vault.lock()
    with pytest.raises(Locked):
        vault.decrypt_json(sealed)


def test_verifying_does_not_count_as_opening(vault):
    vault.setup("hunter2")
    assert vault.verify("nope") is False
    assert vault.verify("hunter2") is True


def test_a_second_vault_reads_the_same_file(vault, tmp_path):
    vault.setup("hunter2")
    sealed = vault.encrypt_json({"x": "y"})
    again = Vault(tmp_path / "security.json")
    assert again.configured is True
    assert again.locked is True
    assert again.unlock("hunter2") is True
    assert again.decrypt_json(sealed) == {"x": "y"}


def test_guessing_gets_slower(vault, monkeypatch):
    slept: list[float] = []
    monkeypatch.setattr("webscripts.vault.time.sleep", slept.append)
    vault.setup("hunter2")
    for _ in range(8):
        vault.unlock("wrong")
    assert slept and max(slept) > 0


def test_windows_only_doors_say_so_elsewhere(vault):
    vault.setup("hunter2")
    with pytest.raises(VaultError):
        vault.set_windows_password(True, "whatever")
    with pytest.raises(VaultError):
        vault.set_biometric(True)
    assert vault.state()["windows_enabled"] is False


def test_the_state_never_carries_a_secret(vault):
    vault.setup("hunter2")
    assert "hunter2" not in json.dumps(vault.state(), ensure_ascii=False)


# ---------------------------------------------------------------- credentials


@pytest.fixture()
def credentials(vault, tmp_path):
    vault.setup("hunter2")
    return CredentialStore(vault, tmp_path / "credentials.json")


def test_an_account_password_is_stored_encrypted(credentials, tmp_path):
    credentials.set("acc_1", "elyas@example.com", "s3cret!", "کاري")
    raw = (tmp_path / "credentials.json").read_text("utf-8")
    assert "s3cret!" not in raw
    assert "elyas@example.com" not in raw


def test_the_list_says_that_something_is_saved_without_saying_what(credentials):
    credentials.set("acc_1", "elyas", "s3cret")
    summary = credentials.summary("acc_1")
    assert summary == {
        "has_username": True, "has_password": True, "has_note": False,
        "updated_at": summary["updated_at"],
    }
    assert credentials.saved() == {"acc_1"}


def test_the_details_come_back_whole(credentials):
    credentials.set("acc_1", "elyas", "s3cret", "یادونه")
    assert credentials.reveal("acc_1") == {
        "username": "elyas", "password": "s3cret", "note": "یادونه",
    }


def test_an_account_with_nothing_saved_reveals_nothing(credentials):
    assert credentials.reveal("acc_nope")["username"] == ""


def test_saving_blanks_clears_the_entry(credentials):
    credentials.set("acc_1", "elyas", "s3cret")
    credentials.set("acc_1", "", "", "")
    assert credentials.saved() == set()


def test_locking_the_app_closes_the_details(credentials, vault):
    credentials.set("acc_1", "elyas", "s3cret")
    vault.lock()
    with pytest.raises(Locked):
        credentials.reveal("acc_1")
