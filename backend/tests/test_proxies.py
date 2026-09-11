"""Proxies: parsing what sellers hand out, and keeping one per account."""

from __future__ import annotations

import random
import stat

import pytest

from webscripts.proxies import (
    ALIVE,
    DEAD,
    Proxy,
    ProxyStore,
    distribute,
    parse_line,
    parse_many,
)


@pytest.fixture()
def store(tmp_path):
    return ProxyStore(tmp_path / "proxies.json")


# ------------------------------------------------------------------ parsing


def test_the_shape_webshare_hands_out():
    # 203.0.113.x is the documentation range: nothing here is a real seller's
    # address, and no real credential belongs in a repository.
    proxy = parse_line("203.0.113.11:6754:someuser:secret")

    assert (proxy.host, proxy.port) == ("203.0.113.11", 6754)
    assert (proxy.username, proxy.password) == ("someuser", "secret")
    assert proxy.scheme == "http"
    assert proxy.needs_auth


def test_a_bare_address_needs_no_credentials():
    proxy = parse_line("1.2.3.4:8080")

    assert (proxy.host, proxy.port) == ("1.2.3.4", 8080)
    assert not proxy.needs_auth


def test_credentials_in_front_of_the_address():
    proxy = parse_line("user:pw@proxy.example.com:3128")

    assert proxy.host == "proxy.example.com"
    assert (proxy.username, proxy.password) == ("user", "pw")


def test_a_full_url_keeps_its_scheme():
    proxy = parse_line("socks5://u:p@1.2.3.4:1080")

    assert proxy.scheme == "socks5"
    assert proxy.url() == "socks5://u:p@1.2.3.4:1080"


def test_nonsense_is_rejected_rather_than_guessed():
    assert parse_line("hello") is None
    assert parse_line("1.2.3.4") is None
    assert parse_line("1.2.3.4:99999") is None
    assert parse_line("# a comment") is None


def test_a_pasted_list_reports_the_lines_it_could_not_read():
    proxies, bad = parse_many(
        "1.2.3.4:8080\n\nnot a proxy\n5.6.7.8:9090:u:p\n"
    )

    assert [p.address for p in proxies] == ["1.2.3.4:8080", "5.6.7.8:9090"]
    assert bad == ["not a proxy"]


# ------------------------------------------------------------------ storage


def test_the_same_proxy_is_not_added_twice(store):
    first, _ = parse_many("1.2.3.4:8080\n5.6.7.8:9090")
    store.add_many(first)

    again, _ = parse_many("1.2.3.4:8080\n9.9.9.9:1111")
    added, skipped = store.add_many(again)

    assert [p.address for p in added] == ["9.9.9.9:1111"]
    assert skipped == 1
    assert len(store.list()) == 3


def test_the_file_is_readable_only_by_its_owner(store):
    """It holds proxy passwords, like the cookie files next to it."""
    store.add_many(parse_many("1.2.3.4:8080:user:pw")[0])

    mode = stat.S_IMODE(store.path.stat().st_mode)

    assert mode == 0o600


def test_the_password_never_leaves_in_a_summary(store):
    added, _ = store.add_many(parse_many("1.2.3.4:8080:user:pw")[0])

    summary = added[0].summary()

    assert "password" not in summary
    assert summary["has_password"] is True


def test_a_check_result_is_remembered(store):
    added, _ = store.add_many(parse_many("1.2.3.4:8080")[0])

    store.set_status(added[0].id, ALIVE, latency_ms=240, exit_ip="9.9.9.9",
                     country="Germany", city="Berlin")

    proxy = store.get(added[0].id)
    assert (proxy.status, proxy.latency_ms, proxy.exit_ip) == (ALIVE, 240, "9.9.9.9")
    assert proxy.checked_at is not None


def test_a_dead_proxy_is_never_picked_for_a_run(store):
    added, _ = store.add_many(parse_many("1.2.3.4:8080\n5.6.7.8:9090")[0])
    store.set_status(added[0].id, DEAD)

    assert [p.address for p in store.usable()] == ["5.6.7.8:9090"]


def test_a_disabled_proxy_is_left_alone(store):
    added, _ = store.add_many(parse_many("1.2.3.4:8080")[0])
    store.update(added[0].id, enabled=False)

    assert store.usable() == []
    assert store.random_usable() is None


def test_deleting_one_leaves_the_rest(store):
    added, _ = store.add_many(parse_many("1.2.3.4:8080\n5.6.7.8:9090")[0])

    assert store.delete(added[0].id)
    assert not store.delete("prx_nope")
    assert len(store.list()) == 1


# --------------------------------------------------------------- assignment


def test_every_account_gets_its_own_proxy():
    proxies = [Proxy(host=f"10.0.0.{i}", port=8080) for i in range(3)]

    plan = distribute(proxies, ["a1", "a2", "a3"], random.Random(1))

    assert sorted(plan) == ["a1", "a2", "a3"]
    assert len(set(plan.values())) == 3


def test_fewer_proxies_than_accounts_wraps_around():
    proxies = [Proxy(host="10.0.0.1", port=8080), Proxy(host="10.0.0.2", port=8080)]

    plan = distribute(proxies, ["a1", "a2", "a3"], random.Random(1))

    assert len(plan) == 3
    assert len(set(plan.values())) == 2


def test_nothing_to_hand_out_is_not_an_error():
    assert distribute([], ["a1"]) == {}
    assert distribute([Proxy(host="1.1.1.1", port=1)], []) == {}
