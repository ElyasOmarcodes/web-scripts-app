"""Reading the kind of address out of the lookup, and warning about a move."""

from __future__ import annotations

import json
import types

import pytest

from webscripts import proxy_check
from webscripts.proxies import DATACENTRE, MOBILE, RESIDENTIAL, Proxy


def _answer(monkeypatch, body: dict) -> None:
    monkeypatch.setattr(
        proxy_check, "_read_through", lambda proxy, url, timeout: body
    )


def test_the_lookup_is_asked_for_what_kind_of_address_it_is():
    wanted = proxy_check.LOOKUPS[0][0]
    for field in ("hosting", "proxy", "mobile", "isp"):
        assert field in wanted


def test_a_server_farm_address_comes_back_as_a_data_centre(monkeypatch):
    _answer(monkeypatch, {
        "query": "203.0.113.5", "country": "Germany", "city": "Falkenstein",
        "isp": "Hetzner Online GmbH", "hosting": True, "proxy": False,
        "mobile": False,
    })
    found = proxy_check.check(Proxy(host="h", port=1))
    assert found["kind"] == DATACENTRE
    assert found["isp"].startswith("Hetzner")
    assert found["flagged"] is False


def test_a_known_proxy_address_is_flagged(monkeypatch):
    _answer(monkeypatch, {
        "query": "203.0.113.6", "isp": "Some ISP", "proxy": True,
    })
    assert proxy_check.check(Proxy(host="h", port=1))["flagged"] is True


def test_a_phone_network_beats_everything(monkeypatch):
    _answer(monkeypatch, {
        "query": "203.0.113.7", "isp": "Vodafone", "mobile": True,
        "hosting": True,
    })
    assert proxy_check.check(Proxy(host="h", port=1))["kind"] == MOBILE


def test_a_home_line_is_recognised(monkeypatch):
    _answer(monkeypatch, {"query": "203.0.113.8", "isp": "Deutsche Telekom"})
    assert proxy_check.check(Proxy(host="h", port=1))["kind"] == RESIDENTIAL


def test_a_lookup_that_says_nothing_claims_nothing(monkeypatch):
    _answer(monkeypatch, {"query": "203.0.113.9"})
    found = proxy_check.check(Proxy(host="h", port=1))
    assert found["kind"] == "unknown"
    assert found["flagged"] is False
