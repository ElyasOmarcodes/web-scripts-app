"""What a proxy check concludes, without touching the network."""

from __future__ import annotations

import socket
import urllib.error

import pytest

from webscripts import proxy_check
from webscripts.proxies import Proxy


def fake_reader(result=None, error=None):
    def read(proxy, url, timeout):
        if error is not None:
            raise error
        return result
    return read


@pytest.fixture()
def proxy():
    return Proxy(host="1.2.3.4", port=8080, username="u", password="p")


def test_a_working_proxy_reports_where_it_comes_out(proxy, monkeypatch):
    monkeypatch.setattr(proxy_check, "_read_through", fake_reader(
        {"status": "success", "query": "203.0.113.24", "country": "Germany",
         "city": "Frankfurt"}
    ))

    result = proxy_check.check(proxy)

    assert result["status"] == "alive"
    assert result["exit_ip"] == "203.0.113.24"
    assert (result["country"], result["city"]) == ("Germany", "Frankfurt")
    assert result["latency_ms"] >= 0


def test_wrong_credentials_are_the_proxys_fault_not_the_networks(proxy, monkeypatch):
    monkeypatch.setattr(proxy_check, "_read_through", fake_reader(
        error=urllib.error.HTTPError("u", 407, "Proxy Auth", None, None)
    ))

    result = proxy_check.check(proxy)

    assert result["status"] == "dead"
    assert "407" in result["note"]


def test_a_proxy_that_never_answers_is_dead(proxy, monkeypatch):
    monkeypatch.setattr(proxy_check, "_read_through",
                        fake_reader(error=socket.timeout("timed out")))

    result = proxy_check.check(proxy)

    assert result["status"] == "dead"
    assert "وخت" in result["note"]


def test_a_refused_connection_is_dead(proxy, monkeypatch):
    monkeypatch.setattr(proxy_check, "_read_through", fake_reader(
        error=urllib.error.URLError("Connection refused")
    ))

    assert proxy_check.check(proxy)["status"] == "dead"


def test_a_socks_proxy_is_left_unknown_rather_than_called_dead():
    """It works in the browser; it just cannot be measured from here."""
    result = proxy_check.check(Proxy(host="1.2.3.4", port=1080, scheme="socks5"))

    assert result["status"] == "unknown"
    assert "SOCKS" in result["note"]


def test_a_nonsense_answer_does_not_count_as_alive(proxy, monkeypatch):
    monkeypatch.setattr(proxy_check, "_read_through",
                        fake_reader({"status": "fail"}))

    assert proxy_check.check(proxy)["status"] == "dead"
