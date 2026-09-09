"""Browser detection and the settings store."""

from __future__ import annotations

import pytest

from webscripts import browsers
from webscripts.browsers import BrowserInfo, BrowserNotFound
from webscripts.settings import Settings, SettingsStore


@pytest.fixture(autouse=True)
def clear_cache():
    browsers._CACHE = None
    yield
    browsers._CACHE = None


def fake_detect(*installed_ids: str):
    def _detect(refresh: bool = False, with_version: bool = True):
        out = []
        for browser_id, (name, family, _, _) in browsers.CATALOG.items():
            found = browser_id in installed_ids
            out.append(
                BrowserInfo(
                    id=browser_id,
                    name=name,
                    family=family,
                    path=f"/fake/{browser_id}" if found else "",
                    installed=found,
                    supported=family in browsers.SUPPORTED_FAMILIES,
                )
            )
        return out

    return _detect


def test_detect_lists_every_known_browser():
    found = browsers.detect(refresh=True, with_version=False)

    assert {b.id for b in found} == set(browsers.CATALOG)
    assert all(isinstance(b.installed, bool) for b in found)


def test_detect_marks_firefox_unsupported():
    firefox = next(b for b in browsers.detect(refresh=True, with_version=False)
                   if b.id == "firefox")
    assert firefox.supported is False


def test_installed_only_returns_supported(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect("firefox", "chrome"))

    assert [b.id for b in browsers.installed()] == ["chrome"]


def test_auto_prefers_edge(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect("chrome", "edge", "brave"))

    assert browsers.resolve("auto").id == "edge"


def test_auto_falls_back_to_chrome(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect("brave", "chrome"))

    assert browsers.resolve("auto").id == "chrome"


def test_explicit_choice_is_honoured(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect("edge", "brave"))

    assert browsers.resolve("brave").id == "brave"


def test_choosing_a_missing_browser_explains_why(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect("edge"))

    with pytest.raises(BrowserNotFound) as error:
        browsers.resolve("chrome")

    assert "Google Chrome" in str(error.value)


def test_no_browser_at_all_is_an_error(monkeypatch):
    monkeypatch.setattr(browsers, "detect", fake_detect())

    with pytest.raises(BrowserNotFound):
        browsers.resolve("auto")


# ----------------------------------------------------------------- settings


def test_defaults_when_no_file(tmp_path):
    store = SettingsStore(tmp_path / "settings.json")

    settings = store.load()

    assert settings.browser == "auto"
    assert settings.speed == 1.0
    assert settings.use_profile is True


def test_update_persists(tmp_path):
    path = tmp_path / "settings.json"
    SettingsStore(path).update({"browser": "chrome", "speed": 2.5})

    reloaded = SettingsStore(path).load()

    assert reloaded.browser == "chrome"
    assert reloaded.speed == 2.5
    # untouched fields keep their defaults
    assert reloaded.headless is False


def test_update_ignores_none_values(tmp_path):
    store = SettingsStore(tmp_path / "settings.json")
    store.update({"browser": "edge"})

    store.update({"browser": None, "headless": True})

    assert store.load().browser == "edge"
    assert store.load().headless is True


def test_out_of_range_speed_is_rejected(tmp_path):
    store = SettingsStore(tmp_path / "settings.json")

    with pytest.raises(Exception):
        store.update({"speed": 99})


def test_corrupt_file_falls_back_to_defaults(tmp_path):
    path = tmp_path / "settings.json"
    path.write_text("{ broken", "utf-8")

    assert SettingsStore(path).load() == Settings()
