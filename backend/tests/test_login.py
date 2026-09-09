"""Sign-in detection and cookie replay, driven by a fake WebDriver."""

from __future__ import annotations

import threading

import pytest

from webscripts.accounts import AccountStore, Category
from webscripts.login import (
    apply_cookies,
    capture_cookies,
    read_display_name,
    signed_in,
    wait_for_login,
)

FACEBOOK = Category(
    id="facebook",
    name="فیسبوک",
    login_url="https://www.facebook.com/login",
    domains=["facebook.com"],
    session_cookies=["c_user", "xs"],
)


class FakeDriver:
    """Hands out a scripted sequence of cookie sets, one per poll."""

    def __init__(self, sequence: list[list[dict]], title: str = "Facebook") -> None:
        self.sequence = sequence
        self.title = title
        self.visited: list[str] = []
        self.added: list[dict] = []
        self._reads = 0

    def get_cookies(self) -> list[dict]:
        index = min(self._reads, len(self.sequence) - 1)
        self._reads += 1
        return self.sequence[index]

    def get(self, url: str) -> None:
        self.visited.append(url)

    def add_cookie(self, cookie: dict) -> None:
        self.added.append(cookie)


@pytest.fixture()
def store(tmp_path):
    return AccountStore(tmp_path / "accounts.json")


def test_capture_keeps_only_this_sites_cookies():
    driver = FakeDriver([[
        {"name": "c_user", "domain": ".facebook.com"},
        {"name": "NID", "domain": ".google.com"},
    ]])

    kept = capture_cookies(driver, FACEBOOK)

    assert [c["name"] for c in kept] == ["c_user"]


def test_signed_in_needs_a_session_cookie():
    assert signed_in(FakeDriver([[{"name": "c_user", "domain": ".facebook.com"}]]), FACEBOOK)
    assert not signed_in(FakeDriver([[{"name": "locale", "domain": ".facebook.com"}]]), FACEBOOK)


def test_wait_for_login_returns_once_the_session_appears():
    logged_out = [{"name": "locale", "domain": ".facebook.com"}]
    logged_in = [
        {"name": "locale", "domain": ".facebook.com"},
        {"name": "c_user", "value": "42", "domain": ".facebook.com"},
    ]
    driver = FakeDriver([logged_out, logged_out, logged_in])

    cookies = wait_for_login(
        driver, FACEBOOK, lambda: False, poll=0.01, settle=0.01
    )

    assert {c["name"] for c in cookies} == {"locale", "c_user"}


def test_wait_for_login_stops_when_cancelled():
    driver = FakeDriver([[{"name": "locale", "domain": ".facebook.com"}]])
    stop = threading.Event()
    stop.set()

    cookies = wait_for_login(driver, FACEBOOK, stop.is_set, poll=0.01)

    # Whatever was there is returned, but it carries no session.
    assert [c["name"] for c in cookies] == ["locale"]


def test_display_name_is_cleaned_up():
    assert read_display_name(FakeDriver([[]], title="(3) Facebook")) == "3 Facebook"


def test_apply_cookies_visits_each_domain_once(store):
    account = store.create("facebook")
    store.save_cookies(account.id, [
        {"name": "c_user", "value": "42", "domain": ".facebook.com", "path": "/"},
        {"name": "xs", "value": "abc", "domain": ".facebook.com", "path": "/"},
        {"name": "sb", "value": "z", "domain": "www.facebook.com", "path": "/"},
    ])
    driver = FakeDriver([[]])

    applied = apply_cookies(driver, store, account, FACEBOOK)

    assert applied == 3
    assert sorted(driver.visited) == [
        "https://facebook.com/",
        "https://www.facebook.com/",
    ]
    # add_cookie() rejects an explicit domain, so it is stripped.
    assert all("domain" not in c for c in driver.added)
    assert {c["name"] for c in driver.added} == {"c_user", "xs", "sb"}


def test_apply_cookies_marks_the_account_used(store):
    account = store.create("facebook")
    store.save_cookies(account.id, [{"name": "c_user", "domain": ".facebook.com"}])

    apply_cookies(FakeDriver([[]]), store, account, FACEBOOK)

    assert store.get(account.id).last_used_at is not None


def test_apply_cookies_without_a_saved_session_is_a_no_op(store):
    account = store.create("facebook")
    driver = FakeDriver([[]])

    assert apply_cookies(driver, store, account, FACEBOOK) == 0
    assert driver.visited == []


def test_unknown_cookie_fields_are_dropped(store):
    account = store.create("facebook")
    store.save_cookies(account.id, [{
        "name": "c_user",
        "value": "42",
        "domain": ".facebook.com",
        "sameSite": "None",
        "expiry": 1893456000.0,
        "priority": "high",       # Chrome extra, not accepted by add_cookie
        "sourceScheme": "Secure",
    }])

    apply_cookies(FakeDriver([[]]), store, account, FACEBOOK)

    sent = FakeDriver([[]])
    apply_cookies(sent, store, account, FACEBOOK)
    cookie = sent.added[0]
    assert set(cookie) <= {"name", "value", "path", "secure", "httpOnly", "expiry", "sameSite"}
    assert cookie["expiry"] == 1893456000
