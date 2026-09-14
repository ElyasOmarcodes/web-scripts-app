"""Saying so before the run when an account is about to change address."""

from __future__ import annotations

import pytest

from webscripts.accounts import AccountStore
from webscripts.proxies import DATACENTRE, ProxyStore, parse_line
from webscripts.session import SessionManager
from webscripts.settings import SettingsStore
from webscripts.storage import Storage
from webscripts.tasks import TaskStore


@pytest.fixture()
def manager(tmp_path):
    accounts = AccountStore(tmp_path / "accounts.json")
    proxies = ProxyStore(tmp_path / "proxies.json")
    made = SessionManager(
        Storage(tmp_path / "scripts"),
        SettingsStore(tmp_path / "settings.json"),
        accounts,
        TaskStore(tmp_path / "tasks.json"),
        proxies,
    )
    # Catch what the run would have told the user.
    made.said = []
    made.bus.subscribe(lambda event: made.said.append(event))
    return made


def said(manager) -> str:
    return " ".join(str(event.get("message", "")) for event in manager.said)


def test_an_account_that_has_not_moved_is_not_nagged(manager):
    account = manager.accounts.create("facebook")
    manager.accounts.update(
        account.id, session_ip="direct", session_place="د کمپیوټر خپله پته"
    )
    manager._announce_proxy(manager.accounts.get(account.id), None)  # noqa: SLF001
    assert "ننوتی و" not in said(manager)


def test_moving_from_home_to_a_proxy_is_announced_before_the_run(manager):
    account = manager.accounts.create("facebook")
    manager.accounts.update(
        account.id, session_ip="direct", session_place="د کمپیوټر خپله پته"
    )
    proxy = parse_line("203.0.113.5:8080")
    manager.proxies.add_many([proxy])
    manager.proxies.set_status(
        proxy.id, "alive", exit_ip="203.0.113.5", country="Germany"
    )
    manager._announce_proxy(  # noqa: SLF001
        manager.accounts.get(account.id), manager.proxies.get(proxy.id)
    )
    message = said(manager)
    assert "ننوتی و" in message
    assert "Germany" in message


def test_a_data_centre_proxy_is_called_out_as_the_likely_cause(manager):
    account = manager.accounts.create("facebook")
    proxy = parse_line("203.0.113.5:8080")
    manager.proxies.add_many([proxy])
    manager.proxies.set_status(
        proxy.id, "alive", exit_ip="203.0.113.5", kind=DATACENTRE
    )
    manager._announce_proxy(  # noqa: SLF001
        manager.accounts.get(account.id), manager.proxies.get(proxy.id)
    )
    assert "ډېټاسنټر" in said(manager)


def test_an_account_that_never_signed_in_anywhere_is_left_alone(manager):
    account = manager.accounts.create("facebook")
    manager._announce_proxy(account, None)  # noqa: SLF001
    assert "ننوتی و" not in said(manager)


def test_the_address_a_session_was_born_at_is_recorded(manager):
    assert manager._where_from(None) == (  # noqa: SLF001
        "direct", "د کمپیوټر خپله پته"
    )
    proxy = parse_line("203.0.113.5:8080")
    proxy.exit_ip = "198.51.100.9"
    proxy.country = "Germany"
    proxy.city = "Berlin"
    assert manager._where_from(proxy) == (  # noqa: SLF001
        "198.51.100.9", "Germany · Berlin"
    )
