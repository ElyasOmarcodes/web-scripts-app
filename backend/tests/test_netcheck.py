"""Turning Chrome's grey "no internet" page into a sentence."""

from __future__ import annotations

from webscripts import netcheck
from webscripts.proxies import Proxy

PROXY = Proxy(host="203.0.113.7", port=8080, username="u", password="p")


class FakeDriver:
    def __init__(self, error: str = "", url: str = "https://example.com") -> None:
        self.error = error
        self.current_url = url

    def execute_script(self, _script):
        return self.error


def test_reads_the_error_code_off_the_page():
    assert netcheck.read(FakeDriver("ERR_PROXY_CONNECTION_FAILED")) == \
        "ERR_PROXY_CONNECTION_FAILED"


def test_a_healthy_page_reports_nothing():
    assert netcheck.read(FakeDriver("")) == ""
    assert netcheck.trouble(FakeDriver(""), PROXY) == ""


def test_a_chrome_error_url_counts_even_without_a_code():
    driver = FakeDriver("", url="chrome-error://chromewebdata/")
    assert netcheck.read(driver) == "ERR_FAILED"


def test_a_proxy_failure_names_the_proxy_and_the_likely_cause():
    message = netcheck.trouble(
        FakeDriver("ERR_TUNNEL_CONNECTION_FAILED"), PROXY, "https://facebook.com"
    )
    assert "203.0.113.7:8080" in message
    assert "اجازه‌لیست" in message  # the whitelist, the usual culprit
    assert "facebook.com" in message


def test_a_site_failure_does_not_blame_the_proxy():
    message = netcheck.trouble(FakeDriver("ERR_CONNECTION_REFUSED"), PROXY)
    assert "اړیکه رد شوه" in message
    assert "اجازه‌لیست" not in message


def test_reads_the_code_out_of_a_selenium_error():
    exc = Exception("unknown error: net::ERR_NAME_NOT_RESOLVED (Session info: …)")
    message = netcheck.from_exception(exc, None)
    assert "DNS" in message


def test_no_code_means_no_message():
    assert netcheck.from_exception(Exception("element not found"), PROXY) == ""


def test_a_driver_without_a_page_does_not_raise():
    class Broken:
        @property
        def current_url(self):
            raise RuntimeError("no session")

        def execute_script(self, _script):
            raise RuntimeError("no session")

    assert netcheck.read(Broken()) == ""
