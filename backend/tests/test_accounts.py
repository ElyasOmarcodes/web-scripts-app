"""Account store, limits and cookie handling."""

from __future__ import annotations

import json

import pytest

from webscripts.accounts import (
    PENDING,
    READY,
    AccountLimitReached,
    AccountStore,
    Category,
    belongs_to,
    has_session,
)


@pytest.fixture()
def store(tmp_path):
    return AccountStore(tmp_path / "accounts.json")


def test_default_categories_match_the_users_limits(store):
    limits = {c.id: c.max_accounts for c in store.categories()}

    assert limits["facebook"] == 2
    assert limits["x"] == 3
    assert limits["instagram"] == 1


def test_create_and_list(store):
    store.create("facebook", "کاري")
    store.create("facebook")

    accounts = store.accounts("facebook")
    assert [a.label for a in accounts] == ["کاري", "فیسبوک 1"]
    assert all(a.status == PENDING for a in accounts)


def test_limit_is_enforced(store):
    store.create("instagram")
    store.save_cookies(store.accounts("instagram")[0].id, [{"name": "sessionid"}])

    with pytest.raises(AccountLimitReached) as error:
        store.create("instagram")

    assert "انسټاګرام" in str(error.value)


def test_pending_accounts_do_not_use_up_the_limit(store):
    # A sign-in that was never completed must not block the next attempt.
    store.create("instagram")

    assert store.count("instagram") == 0
    store.create("instagram")  # does not raise


def test_raising_the_limit_allows_more(store):
    first = store.create("instagram")
    store.save_cookies(first.id, [{"name": "sessionid"}])

    store.set_limit("instagram", 3)
    second = store.create("instagram")

    assert second.category == "instagram"
    assert store.category("instagram").max_accounts == 3


def test_limit_is_clamped(store):
    assert store.set_limit("facebook", 0).max_accounts == 1
    assert store.set_limit("facebook", 999).max_accounts == 20


def test_cookies_are_saved_privately(store):
    account = store.create("facebook")

    saved = store.save_cookies(
        account.id, [{"name": "c_user", "value": "1", "domain": ".facebook.com"}]
    )

    assert saved == 1
    assert store.get(account.id).status == READY
    assert store.get(account.id).cookie_count == 1
    assert json.loads(account.cookie_file.read_text("utf-8"))[0]["name"] == "c_user"
    # owner-only permissions
    assert oct(account.cookie_file.stat().st_mode)[-3:] == "600"


def test_delete_removes_the_cookie_file(store):
    account = store.create("facebook")
    store.save_cookies(account.id, [{"name": "c_user"}])
    path = account.cookie_file

    assert store.delete(account.id) is True
    assert store.get(account.id) is None
    assert not path.exists()


def test_limits_survive_a_reload(tmp_path):
    path = tmp_path / "accounts.json"
    first = AccountStore(path)
    first.set_limit("x", 5)
    account = first.create("x", "دویم")
    first.save_cookies(account.id, [{"name": "auth_token"}])

    second = AccountStore(path)

    assert second.category("x").max_accounts == 5
    assert [a.label for a in second.accounts("x")] == ["دویم"]


def test_overview_reports_usage(store):
    account = store.create("facebook")
    store.save_cookies(account.id, [{"name": "c_user"}])

    overview = store.overview()
    facebook = next(c for c in overview["categories"] if c["id"] == "facebook")

    assert facebook["used"] == 1
    assert facebook["full"] is False
    assert overview["accounts"][0]["has_cookies"] is True


def test_corrupt_file_falls_back_to_defaults(tmp_path):
    path = tmp_path / "accounts.json"
    path.write_text("{ broken", "utf-8")

    store = AccountStore(path)

    assert store.accounts() == []
    assert store.category("facebook").max_accounts == 2


# ------------------------------------------------------------- cookie logic

FACEBOOK = Category(
    id="facebook",
    name="فیسبوک",
    login_url="https://facebook.com/login",
    domains=["facebook.com"],
    session_cookies=["c_user", "xs"],
)


def test_session_detected_from_the_named_cookie():
    assert has_session([{"name": "c_user"}], FACEBOOK) is True
    assert has_session([{"name": "locale"}], FACEBOOK) is False
    assert has_session([], FACEBOOK) is False


def test_domain_matching_covers_subdomains():
    assert belongs_to({"domain": ".facebook.com"}, FACEBOOK) is True
    assert belongs_to({"domain": "www.facebook.com"}, FACEBOOK) is True
    assert belongs_to({"domain": "evil-facebook.com"}, FACEBOOK) is False
    assert belongs_to({"domain": "google.com"}, FACEBOOK) is False


def test_category_without_domains_accepts_everything():
    other = Category(id="other", name="بل", login_url="")

    assert belongs_to({"domain": "anything.test"}, other) is True
    assert has_session([{"name": "whatever"}], other) is True
