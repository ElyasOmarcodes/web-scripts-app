"""Taking the data out in a shape a spreadsheet — or a person — can read."""

from __future__ import annotations

import ast
import json

from webscripts import exporting
from webscripts.accounts import Account
from webscripts.models import Script, Step, Target, Variable
from webscripts.proxies import Proxy


def _script() -> Script:
    return Script(
        name="تم بدلول",
        description="د فیسبوک تم",
        start_url="https://facebook.com",
        variables=[Variable(name="password", secret=True),
                   Variable(name="nick", default="Elyas")],
        gap_min_ms=600,
        gap_max_ms=1800,
        steps=[
            Step(action="goto", url="https://facebook.com/settings"),
            Step(action="click", label="منو", targets=[
                Target(type="css", value="#menu"),
                Target(type="xpath", value="//div[@id='menu']"),
            ]),
            Step(action="type", value="{{password}}", secret=True,
                 targets=[Target(value="#pw")]),
            Step(action="select", value="Dark", option_value="dark",
                 targets=[Target(value="select[name=theme]")]),
            Step(action="press_key", value="ENTER"),
            Step(action="click", frame_path=[0], targets=[Target(value="#ok")]),
            Step(action="click", enabled=False, targets=[Target(value="#never")]),
        ],
    )


# ----------------------------------------------------------------- accounts


def test_accounts_csv_carries_the_whole_row():
    account = Account(
        id="acc_1", category="facebook", label="کاري حساب",
        display_name="Elyas", cookie_count=14, cookie_state="alive",
        proxy_id="prx_1", proxy_mode="fixed", fingerprint_id="win-chrome-145",
    )
    proxy = Proxy(id="prx_1", host="203.0.113.11", port=6754, country="Germany")
    text = exporting.accounts_csv(
        [account],
        categories={"facebook": "فیسبوک"},
        proxies={"prx_1": proxy},
        identities={},
    )
    # Excel needs the BOM to read Pashto at all.
    assert text.startswith("﻿")
    rows = exporting.read_rows(text)
    assert rows[0]["label"] == "کاري حساب"
    assert rows[0]["category_name"] == "فیسبوک"
    assert rows[0]["proxy_address"] == "203.0.113.11:6754"
    assert rows[0]["fingerprint_id"] == "win-chrome-145"


def test_passwords_stay_out_unless_they_are_asked_for():
    account = Account(id="acc_1", category="facebook", label="یو")
    without = exporting.read_rows(exporting.accounts_csv([account]))
    assert without[0]["password"] == ""
    with_them = exporting.read_rows(exporting.accounts_csv(
        [account], secrets={"acc_1": {"username": "u", "password": "p"}}
    ))
    assert with_them[0]["password"] == "p"


def test_accounts_come_back_from_a_csv():
    text = exporting.accounts_csv([
        Account(id="acc_1", category="facebook", label="یو"),
    ])
    rows, problems = exporting.accounts_from_csv(text)
    assert problems == []
    assert rows[0]["category"] == "facebook"
    assert rows[0]["label"] == "یو"


def test_a_row_without_a_category_is_reported_not_guessed():
    rows, problems = exporting.accounts_from_csv("label,category\nیو,\n")
    assert rows == []
    assert "کرښه 2" in problems[0]


def test_an_empty_file_is_not_an_error():
    assert exporting.accounts_from_csv("") == ([], [])


def test_semicolons_are_understood_too():
    # Excel in a European locale writes semicolons, not commas.
    rows, _ = exporting.accounts_from_csv("category;label\nfacebook;یو\n")
    assert rows[0]["label"] == "یو"


# ------------------------------------------------------------------ proxies


def test_proxy_passwords_are_left_out_by_default():
    proxy = Proxy(host="203.0.113.11", port=6754, username="u", password="p")
    plain = exporting.read_rows(exporting.proxies_csv([proxy]))
    assert plain[0]["username"] == "u" and plain[0]["password"] == ""
    full = exporting.read_rows(
        exporting.proxies_csv([proxy], with_passwords=True)
    )
    assert full[0]["password"] == "p"


def test_a_proxy_csv_turns_back_into_lines_the_parser_reads():
    proxy = Proxy(host="203.0.113.11", port=6754, username="u", password="p")
    lines, problems = exporting.proxies_from_csv(
        exporting.proxies_csv([proxy], with_passwords=True)
    )
    assert problems == []
    assert lines == ["http://u:p@203.0.113.11:6754"]


def test_a_proxy_row_without_a_port_is_reported():
    _, problems = exporting.proxies_from_csv("host,port\n203.0.113.11,\n")
    assert problems


# ------------------------------------------------------------------ scripts


def test_scripts_json_round_trips_exactly():
    original = _script()
    back, problems = exporting.scripts_from_json(
        exporting.scripts_json([original])
    )
    assert problems == []
    assert back[0].name == original.name
    assert len(back[0].steps) == len(original.steps)
    assert back[0].steps[1].targets[1].value == "//div[@id='menu']"


def test_a_broken_file_is_reported_not_raised():
    scripts, problems = exporting.scripts_from_json("{not json")
    assert scripts == [] and problems


def test_a_bare_script_object_is_accepted():
    scripts, _ = exporting.scripts_from_json(
        json.dumps(_script().model_dump(), ensure_ascii=False)
    )
    assert len(scripts) == 1


def test_the_python_export_is_real_python():
    code = exporting.script_to_python(_script())
    ast.parse(code)  # raises if it is not
    assert "def run(driver):" in code
    assert "webdriver.Chrome" in code


def test_the_python_export_keeps_every_locator_candidate():
    code = exporting.script_to_python(_script())
    assert "'#menu'" in code and "//div[@id='menu']" in code


def test_a_password_step_exports_as_a_variable_not_a_password():
    code = exporting.script_to_python(_script())
    assert "VARIABLES['password']" in code
    assert '"password": ""' in code  # nothing is filled in for a secret


def test_the_export_keeps_the_random_pause():
    code = exporting.script_to_python(_script())
    assert "GAP = (0.60, 1.80)" in code
    assert code.count("pause()") > 3


def test_a_disabled_step_is_not_exported():
    code = exporting.script_to_python(_script())
    assert "#never" not in code


def test_iframes_are_entered_in_the_export():
    assert "frame(driver, [0])" in exporting.script_to_python(_script())
    assert "frame(page, [0])" in exporting.script_to_javascript(_script())


def test_the_javascript_export_is_shaped_like_playwright():
    code = exporting.script_to_javascript(_script())
    assert "require('playwright')" in code
    assert "async function run(page)" in code
    assert "await (await find(" in code


def test_the_scripts_overview_csv_counts_the_steps():
    rows = exporting.read_rows(exporting.scripts_csv([_script()]))
    assert rows[0]["steps"] == "7"
    assert rows[0]["enabled_steps"] == "6"


def test_cookies_stay_out_of_the_csv_unless_handed_over():
    account = Account(id="acc_1", category="facebook", label="یو")
    without = exporting.read_rows(exporting.accounts_csv([account]))
    assert without[0]["cookies"] == ""

    session = [{"name": "xs", "value": "token", "domain": ".facebook.com"}]
    with_them = exporting.read_rows(
        exporting.accounts_csv([account], cookies={"acc_1": session})
    )
    assert "token" in with_them[0]["cookies"]


def test_a_carried_session_comes_back_whole():
    account = Account(id="acc_1", category="facebook", label="یو")
    session = [
        {"name": "c_user", "value": "100012345", "domain": ".facebook.com"},
        {"name": "xs", "value": "token", "domain": ".facebook.com"},
    ]
    rows, problems = exporting.accounts_from_csv(
        exporting.accounts_csv([account], cookies={"acc_1": session})
    )
    assert problems == []
    assert rows[0]["cookies"] == session


def test_a_file_without_cookies_imports_with_none():
    account = Account(id="acc_1", category="facebook", label="یو")
    rows, _ = exporting.accounts_from_csv(exporting.accounts_csv([account]))
    assert rows[0]["cookies"] == []


def test_a_damaged_cookie_cell_is_reported_not_swallowed():
    rows, problems = exporting.accounts_from_csv(
        "category,label,cookies\nfacebook,یو,{not json\n"
    )
    assert rows[0]["cookies"] == []
    assert "کرښه 2" in problems[0]
