"""One identity per account, and every identity internally consistent."""

from __future__ import annotations

import json

import pytest

from webscripts import disguise, fingerprints, geo
from webscripts.accounts import AccountStore


def test_catalogue_is_a_hundred_distinct_devices():
    assert len(fingerprints.CATALOGUE) == 100
    assert len({f.id for f in fingerprints.CATALOGUE}) == 100
    assert len({f.ua for f in fingerprints.CATALOGUE}) == 100


def test_every_profile_agrees_with_itself():
    for profile in fingerprints.CATALOGUE:
        # A phone user agent with a desktop screen, or an iPhone that reports
        # Windows, is the mismatch this whole module exists to avoid.
        if "Mobile" in profile.ua or "iPhone" in profile.ua:
            assert profile.touch > 0, profile.id
            assert profile.screen[0] < profile.screen[1], profile.id
        if profile.brand == "Safari":
            # Safari has neither client hints nor deviceMemory.
            assert not profile.has_ua_data, profile.id
            assert profile.memory is None, profile.id
        else:
            assert profile.has_ua_data, profile.id
        assert str(profile.version) in profile.ua, profile.id
        assert profile.webgl_renderer, profile.id


def test_phones_are_never_handed_out_automatically():
    chosen = {
        fingerprints.assign([], f"acc_{index}", 145) for index in range(40)
    }
    for item in chosen:
        assert fingerprints.get(item).tier != fingerprints.BOLD


def test_assignment_spreads_before_it_repeats():
    taken: list[str] = []
    for index in range(21):  # exactly the number of "safe" identities
        taken.append(fingerprints.assign(taken, f"acc_{index}", 145))
    assert len(set(taken)) == len(taken)


def test_assignment_prefers_the_version_we_really_run():
    picked = fingerprints.get(fingerprints.assign([], "acc_x", 138))
    assert abs(picked.version - 138) <= 1


def test_new_accounts_get_their_own_identity(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    first = store.create("facebook")
    second = store.create("facebook")
    assert first.fingerprint_id and second.fingerprint_id
    assert first.fingerprint_id != second.fingerprint_id
    assert first.fingerprint_seed != second.fingerprint_seed


def test_an_identity_never_changes_on_its_own(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    account = store.create("facebook")
    before = (account.fingerprint_id, account.fingerprint_seed)
    store.update(account.id, label="renamed")
    store.backfill_fingerprints(real_version=145)
    again = store.get(account.id)
    assert (again.fingerprint_id, again.fingerprint_seed) == before


def test_old_accounts_are_given_one(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    account = store.create("facebook")
    store.update(account.id, fingerprint_id="", fingerprint_seed=0)
    # update() ignores falsy values, so write the blanks directly.
    store.get(account.id).fingerprint_id = ""
    store.get(account.id).fingerprint_seed = 0
    store._save()  # noqa: SLF001 - the point of the test
    assert store.backfill_fingerprints(145) == 1
    assert store.get(account.id).fingerprint_id


def test_seed_is_derived_from_the_account_id():
    assert fingerprints.stable_seed("acc_1") == fingerprints.stable_seed("acc_1")
    assert fingerprints.stable_seed("acc_1") != fingerprints.stable_seed("acc_2")


# ------------------------------------------------------------------ disguise


def test_client_hints_match_the_user_agent():
    profile = fingerprints.get("win-chrome-140")
    data = disguise.metadata(profile)
    assert data["platform"] == "Windows"
    assert data["mobile"] is False
    assert {"brand": "Google Chrome", "version": "140"} in data["brands"]


def test_safari_sends_no_client_hints():
    profile = fingerprints.get("mac-safari-26")
    assert disguise.brands(profile) == []


def test_script_carries_the_whole_device():
    profile = fingerprints.get("pixel-pixel-9")
    body = disguise.script(profile, 4242, "Germany")
    assert '"seed": 4242' in body
    assert profile.webgl_renderer in body
    assert "de-DE" in body  # the proxy's country decides the language
    assert "RTCPeerConnection" in body  # the WebRTC hole is closed
    assert "geolocation" in body
    config = json.loads(body.split(" = ", 1)[1].split(";\n", 1)[0])
    assert config["cores"] == profile.cores
    assert config["touch"] == profile.touch


def test_the_window_never_exceeds_its_own_screen():
    profile = fingerprints.get("linux-chrome-140")  # claims 1600×900 or less
    assert disguise.fit_screen(profile, (2000, 1300))[0] >= 2000
    assert disguise.fit_screen(profile, (800, 600)) == profile.screen


def test_timezone_follows_the_proxy():
    assert geo.timezone_for("Germany") == "Europe/Berlin"
    assert geo.timezone_for("United States", "Los Angeles") == "America/Los_Angeles"
    assert geo.timezone_for("Nowhereland") == ""


def test_accept_language_header_is_shaped_like_chrome():
    header = geo.accept_language(("de-DE", "de", "en-US", "en"))
    assert header == "de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7"


@pytest.mark.parametrize("fingerprint_id", [f.id for f in fingerprints.CATALOGUE])
def test_every_profile_produces_a_script(fingerprint_id):
    profile = fingerprints.get(fingerprint_id)
    body = disguise.script(profile, 7, "")
    assert body.startswith("const __WS_ID__ = {")
    assert "__WS_ID__" in body


# ------------------------------------------------------- on the real browser


def test_the_browser_is_started_as_the_identity(tmp_path):
    from webscripts import browsers
    from webscripts.driver import build_options

    info = browsers.BrowserInfo(
        id="chrome", name="Chrome", path="/x", family="chromium"
    )
    profile = fingerprints.get("win-chrome-145")
    options = build_options(
        info, use_profile=False, fingerprint=profile, country="Germany"
    )
    arguments = options.arguments
    assert f"--user-agent={profile.ua}" in arguments
    assert "--lang=de-DE" in arguments
    # A stable window, not a maximised one: maximised reports the real screen.
    assert any(a.startswith("--window-size=") for a in arguments)
    # And the hole a proxy cannot close on its own.
    assert "--force-webrtc-ip-handling-policy=disable_non_proxied_udp" in arguments


def test_a_phone_identity_gets_a_phone_sized_window():
    from webscripts import browsers
    from webscripts.driver import build_options

    info = browsers.BrowserInfo(
        id="chrome", name="Chrome", path="/x", family="chromium"
    )
    options = build_options(
        info, use_profile=False, fingerprint=fingerprints.get("pixel-pixel-9")
    )
    size = [a for a in options.arguments if a.startswith("--window-size=")][0]
    width = int(size.split("=")[1].split(",")[0])
    assert width < 500


# ------------------------------------------- never claim to be newer than us


def test_an_identity_never_claims_a_newer_browser_than_the_real_one():
    # The failure this prevents is not "the site noticed" — it is a site
    # sending JavaScript the installed engine cannot run, and a button
    # quietly doing nothing.
    for real in (120, 131, 138, 145):
        picked = fingerprints.get(fingerprints.assign([], "acc_x", real))
        assert picked.version <= real, (real, picked.id)


def test_claiming_older_is_allowed_because_it_is_safe():
    picked = fingerprints.get(fingerprints.assign([], "acc_x", 145))
    assert picked.version <= 145


def test_a_browser_older_than_the_whole_catalogue_still_gets_something():
    assert fingerprints.assign([], "acc_x", 60)


def test_too_new_is_what_the_repair_looks_for():
    assert fingerprints.too_new("win-chrome-145", 138) is True
    assert fingerprints.too_new("win-chrome-131", 138) is False
    assert fingerprints.too_new("win-chrome-145", None) is False
    assert fingerprints.too_new(fingerprints.OFF, 100) is False


def test_new_accounts_follow_the_installed_browser(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    store.browser_version = 132
    account = store.create("facebook")
    assert fingerprints.get(account.fingerprint_id).version <= 132


def test_the_repair_moves_only_the_accounts_that_are_wrong(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    old = store.create("facebook", "زوړ")
    fine = store.create("facebook", "سم")
    store.set_fingerprint(old.id, "win-chrome-145")
    store.set_fingerprint(fine.id, "win-chrome-130")
    store.browser_version = 138

    assert [a.id for a in store.claiming_too_new()] == [old.id]
    assert store.repair_fingerprints() == 1
    assert fingerprints.get(store.get(old.id).fingerprint_id).version <= 138
    # The one that was already fine is left exactly where it was.
    assert store.get(fine.id).fingerprint_id == "win-chrome-130"
    assert store.repair_fingerprints() == 0


# ------------------------------------------------------- switching it off


def test_an_identity_can_be_switched_off_on_purpose(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    account = store.create("facebook")
    store.set_fingerprint(account.id, fingerprints.OFF)
    assert store.get(account.id).fingerprint_id == fingerprints.OFF


def test_off_is_a_choice_and_is_not_quietly_undone(tmp_path):
    store = AccountStore(tmp_path / "accounts.json")
    account = store.create("facebook")
    store.set_fingerprint(account.id, fingerprints.OFF)
    # Every later pass that hands out missing identities must leave it alone.
    assert store.backfill_fingerprints(145) == 0
    assert store.get(account.id).fingerprint_id == fingerprints.OFF


def test_an_account_switched_off_gets_no_disguise():
    # get() returning None is what makes the session open a plain browser.
    assert fingerprints.get(fingerprints.OFF) is None
