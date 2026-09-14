"""Taking the data out, and putting it back in.

Three kinds of thing leave this app, and each wants a different shape:

* **accounts and proxies** → CSV, because that is what a spreadsheet opens.
  Written with a BOM so Excel shows Pashto correctly instead of mojibake, and
  with plain English column names so a file can be edited and imported back
  without the headers having to survive translation.
* **scripts** → their own JSON (which imports back exactly), or real source
  code — Python for Selenium, JavaScript for Playwright — for anyone who wants
  to run a recording outside this app or read what it actually does.

Passwords are never included unless they are asked for by name, and the caller
only gets to ask after the vault has checked who is asking.
"""

from __future__ import annotations

import csv
import io
import json
from typing import Any, Iterable

from .models import Script, Step

ACCOUNT_COLUMNS = [
    "id", "label", "category", "category_name", "display_name", "status",
    "cookie_state", "cookie_count", "cookie_checked_at",
    "proxy_mode", "proxy_address", "proxy_country",
    "fingerprint_id", "fingerprint_label",
    "created_at", "last_used_at",
    "username", "password", "note",
    # The session itself, as JSON in one cell. Off unless asked for: this
    # column *is* the login, so a file carrying it is a file that signs in.
    "cookies",
]

PROXY_COLUMNS = [
    "label", "scheme", "host", "port", "username", "password",
    "enabled", "status", "latency_ms", "exit_ip", "country", "city",
    "used_by", "note",
]

SCRIPT_COLUMNS = [
    "id", "name", "description", "start_url", "steps", "enabled_steps",
    "gap_min_ms", "gap_max_ms", "created_at", "updated_at", "last_run_at",
]


def _write(columns: list[str], rows: Iterable[dict[str, Any]]) -> str:
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in columns})
    # The BOM is what tells Excel the file is UTF-8; without it Pashto arrives
    # as unreadable symbols on a Windows machine.
    return "﻿" + buffer.getvalue()


def read_rows(text: str) -> list[dict[str, str]]:
    """Read a CSV back, whatever it was saved with."""
    cleaned = text.lstrip("﻿")
    if not cleaned.strip():
        return []
    sample = cleaned[:2048]
    try:
        dialect: Any = csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(io.StringIO(cleaned), dialect=dialect)
    rows = []
    for row in reader:
        rows.append({
            (key or "").strip().lower(): (value or "").strip()
            for key, value in row.items()
            if key
        })
    return rows


# ------------------------------------------------------------------ accounts


def accounts_csv(
    accounts: Iterable[Any],
    categories: dict[str, str] | None = None,
    proxies: dict[str, Any] | None = None,
    identities: dict[str, Any] | None = None,
    secrets: dict[str, dict[str, str]] | None = None,
    cookies: dict[str, list[dict[str, Any]]] | None = None,
) -> str:
    categories = categories or {}
    proxies = proxies or {}
    identities = identities or {}
    secrets = secrets or {}
    cookies = cookies or {}
    rows = []
    for account in accounts:
        proxy = proxies.get(account.proxy_id)
        identity = identities.get(account.fingerprint_id)
        secret = secrets.get(account.id, {})
        rows.append({
            "id": account.id,
            "label": account.label,
            "category": account.category,
            "category_name": categories.get(account.category, ""),
            "display_name": account.display_name,
            "status": account.status,
            "cookie_state": account.cookie_state,
            "cookie_count": account.cookie_count,
            "cookie_checked_at": account.cookie_checked_at or "",
            "proxy_mode": account.proxy_mode,
            "proxy_address": getattr(proxy, "address", ""),
            "proxy_country": getattr(proxy, "country", ""),
            "fingerprint_id": account.fingerprint_id,
            "fingerprint_label": getattr(identity, "label", ""),
            "created_at": account.created_at,
            "last_used_at": account.last_used_at or "",
            "username": secret.get("username", ""),
            "password": secret.get("password", ""),
            "note": secret.get("note", ""),
            "cookies": (
                json.dumps(cookies[account.id], ensure_ascii=False)
                if account.id in cookies else ""
            ),
        })
    return _write(ACCOUNT_COLUMNS, rows)


def accounts_from_csv(text: str) -> tuple[list[dict[str, str]], list[str]]:
    """Rows that could be understood, and a line about each that could not."""
    wanted, problems = [], []
    for number, row in enumerate(read_rows(text), start=2):
        category = row.get("category", "")
        label = row.get("label") or row.get("display_name") or ""
        if not category:
            problems.append(f"کرښه {number}: «category» تشه ده")
            continue
        if not label:
            problems.append(f"کرښه {number}: نوم نشته")
            continue
        entry = {
            "category": category,
            "label": label,
            "display_name": row.get("display_name", ""),
            "proxy_mode": row.get("proxy_mode", ""),
            "proxy_address": row.get("proxy_address", ""),
            "fingerprint_id": row.get("fingerprint_id", ""),
            "username": row.get("username", ""),
            "password": row.get("password", ""),
            "note": row.get("note", ""),
            "cookies": [],
        }
        raw = row.get("cookies", "")
        if raw:
            # A file that carries the session restores it; a file that does
            # not simply leaves the account needing one sign-in.
            try:
                parsed = json.loads(raw)
            except ValueError:
                problems.append(f"کرښه {number}: کوکیز ونه لوستل شول")
            else:
                if isinstance(parsed, list):
                    entry["cookies"] = [c for c in parsed if isinstance(c, dict)]
                else:
                    problems.append(f"کرښه {number}: د کوکیزو بڼه ناسمه ده")
        wanted.append(entry)
    return wanted, problems


# ------------------------------------------------------------------- proxies


def proxies_csv(
    proxies: Iterable[Any],
    used_by: dict[str, int] | None = None,
    with_passwords: bool = False,
) -> str:
    used_by = used_by or {}
    rows = []
    for proxy in proxies:
        rows.append({
            "label": proxy.label,
            "scheme": proxy.scheme,
            "host": proxy.host,
            "port": proxy.port,
            "username": proxy.username,
            # A proxy list without its passwords is a list nobody can use
            # again — but it is also the safe thing to hand to anyone, so it
            # is the default and the other way has to be chosen on purpose.
            "password": proxy.password if with_passwords else "",
            "enabled": "yes" if proxy.enabled else "no",
            "status": proxy.status,
            "latency_ms": proxy.latency_ms or "",
            "exit_ip": proxy.exit_ip,
            "country": proxy.country,
            "city": proxy.city,
            "used_by": used_by.get(proxy.id, 0),
            "note": proxy.note,
        })
    return _write(PROXY_COLUMNS, rows)


def proxies_from_csv(text: str) -> tuple[list[str], list[str]]:
    """Turn a CSV back into the plain lines the proxy parser already reads."""
    lines, problems = [], []
    for number, row in enumerate(read_rows(text), start=2):
        host = row.get("host", "")
        port = row.get("port", "")
        if not host or not port:
            problems.append(f"کرښه {number}: پته یا پورټ نشته")
            continue
        scheme = row.get("scheme") or "http"
        user = row.get("username", "")
        password = row.get("password", "")
        if user or password:
            lines.append(f"{scheme}://{user}:{password}@{host}:{port}")
        else:
            lines.append(f"{scheme}://{host}:{port}")
    return lines, problems


# ------------------------------------------------------------------- scripts


def scripts_csv(scripts: Iterable[Script]) -> str:
    return _write(SCRIPT_COLUMNS, [
        {
            "id": script.id,
            "name": script.name,
            "description": script.description,
            "start_url": script.start_url,
            "steps": len(script.steps),
            "enabled_steps": len([s for s in script.steps if s.enabled]),
            "gap_min_ms": script.gap_min_ms or "",
            "gap_max_ms": script.gap_max_ms or "",
            "created_at": script.created_at,
            "updated_at": script.updated_at,
            "last_run_at": script.last_run_at or "",
        }
        for script in scripts
    ])


def scripts_json(scripts: Iterable[Script]) -> str:
    """The only shape that imports back exactly as it left."""
    return json.dumps(
        {
            "kind": "webscripts/scripts",
            "version": 1,
            "scripts": [script.model_dump() for script in scripts],
        },
        ensure_ascii=False,
        indent=2,
    )


def scripts_from_json(text: str) -> tuple[list[Script], list[str]]:
    problems: list[str] = []
    try:
        data = json.loads(text)
    except ValueError as error:
        return [], [f"JSON ونه لوستل شو: {error}"]

    if isinstance(data, dict) and "scripts" in data:
        raw = data.get("scripts") or []
    elif isinstance(data, list):
        raw = data
    elif isinstance(data, dict):
        raw = [data]
    else:
        return [], ["فایل د سکریپټ په بڼه نه دی"]

    scripts = []
    for index, item in enumerate(raw, start=1):
        try:
            script = Script.model_validate(item)
        except Exception as error:  # noqa: BLE001
            problems.append(f"سکریپټ {index}: {str(error).splitlines()[0]}")
            continue
        scripts.append(script)
    return scripts, problems


def _primary(step: Step) -> tuple[str, str]:
    for target in step.targets:
        return target.type, target.value
    return "css", ""


def _targets(step: Step) -> list[list[str]]:
    return [[t.type, t.value] for t in step.targets]


PY_HEADER = '''"""{name}

{description}

Exported from WebScripts. Runs on its own:

    pip install selenium
    python {slug}.py

Every element keeps the same list of locator candidates the app uses, tried
from the most robust to the least, so this survives the small layout changes
that break a single hard-coded selector.
"""

import random
import time

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import Select, WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

TIMEOUT = 15
# The app pauses a random moment between actions, because a run with no pauses
# does not look like a person. Keep it.
GAP = ({gap_min:.2f}, {gap_max:.2f})

VARIABLES = {variables}


def pause():
    time.sleep(random.uniform(*GAP))


def find(driver, candidates):
    """First locator that matches, tried in order."""
    last = None
    for kind, value in candidates:
        by = By.CSS_SELECTOR if kind == "css" else By.XPATH
        try:
            return WebDriverWait(driver, TIMEOUT).until(
                EC.presence_of_element_located((by, value))
            )
        except Exception as error:
            last = error
    raise AssertionError("no locator matched: %r (%s)" % (candidates, last))


def frame(driver, path):
    driver.switch_to.default_content()
    for index in path:
        driver.switch_to.frame(driver.find_elements(By.TAG_NAME, "iframe")[index])


def run(driver):
'''

PY_FOOTER = '''

def main():
    options = webdriver.ChromeOptions()
    options.add_argument("--disable-blink-features=AutomationControlled")
    driver = webdriver.Chrome(options=options)
    try:
        run(driver)
        print("done")
    finally:
        driver.quit()


if __name__ == "__main__":
    main()
'''


def script_to_python(script: Script) -> str:
    gap_min = (script.gap_min_ms or 500) / 1000
    gap_max = (script.gap_max_ms or max(script.gap_min_ms or 500, 1500)) / 1000
    variables = {v.name: ("" if v.secret else v.default) for v in script.variables}
    body: list[str] = []
    frame_now: list[int] = []

    if script.start_url and not (script.steps and script.steps[0].action == "goto"):
        body.append(f"    driver.get({script.start_url!r})")
        body.append("    pause()")

    for step in script.steps:
        if not step.enabled:
            continue
        if step.frame_path != frame_now:
            body.append(f"    frame(driver, {step.frame_path!r})")
            frame_now = list(step.frame_path)
        body.append(f"    # {step.describe()}")
        body.extend(_python_step(step))
        body.append("    pause()")

    if not body:
        body = ["    pass"]
    header = PY_HEADER.format(
        name=script.name,
        description=script.description or "—",
        slug=(script.name or "script").replace(" ", "_"),
        gap_min=gap_min,
        gap_max=gap_max,
        variables=json.dumps(variables, ensure_ascii=False, indent=4),
    )
    return header + "\n".join(body) + "\n" + PY_FOOTER


def _python_step(step: Step) -> list[str]:
    targets = _targets(step)
    value = step.value or ""
    action = step.action

    if action == "goto":
        return [f"    driver.get({step.url or ''!r})"]
    if action == "wait":
        return [f"    time.sleep({max(0.0, float(value or 0) / 1000):.2f})"]
    if action == "switch_window":
        return ["    driver.switch_to.window(driver.window_handles[-1])"]
    if action == "screenshot":
        return [f"    driver.save_screenshot({(value or 'shot') + '.png'!r})"]
    if action == "scroll":
        return [f"    driver.execute_script('window.scrollBy(0, %s)' % {value or 0!r})"]
    if action == "press_key":
        key = (value or "ENTER").upper()
        return [
            f"    find(driver, {targets!r}).send_keys(Keys.{key})"
            if targets
            else f"    webdriver.ActionChains(driver).send_keys(Keys.{key}).perform()"
        ]
    if action == "assert_text":
        return [
            f"    assert {value!r} in find(driver, {targets!r}).text, "
            f"{'missing: ' + value!r}"
        ]
    if action == "select":
        lines = [f"    element = find(driver, {targets!r})"]
        lines.append("    try:")
        lines.append(f"        Select(element).select_by_visible_text({value!r})")
        lines.append("    except Exception:")
        lines.append(
            f"        Select(element).select_by_value({step.option_value or value!r})"
        )
        return lines
    if action == "type":
        source = (
            f"VARIABLES[{_variable_name(value)!r}]"
            if _variable_name(value)
            else repr(value)
        )
        return [
            f"    element = find(driver, {targets!r})",
            "    element.clear()",
            f"    element.send_keys({source})",
        ]
    if action == "hover":
        return [
            f"    webdriver.ActionChains(driver).move_to_element("
            f"find(driver, {targets!r})).perform()"
        ]
    if action in {"double_click", "right_click"}:
        how = "double_click" if action == "double_click" else "context_click"
        return [
            f"    webdriver.ActionChains(driver).{how}("
            f"find(driver, {targets!r})).perform()"
        ]
    return [f"    find(driver, {targets!r}).click()"]


def _variable_name(value: str) -> str:
    text = (value or "").strip()
    if text.startswith("{{") and text.endswith("}}"):
        return text[2:-2].strip()
    return ""


JS_HEADER = """/**
 * {name}
 *
 * {description}
 *
 * Exported from WebScripts. Runs on its own:
 *
 *   npm i playwright && npx playwright install chromium
 *   node {slug}.js
 */
const {{ chromium }} = require('playwright');

const TIMEOUT = 15000;
const GAP = [{gap_min}, {gap_max}];
const VARIABLES = {variables};

const pause = () =>
  new Promise((done) =>
    setTimeout(done, GAP[0] + Math.random() * (GAP[1] - GAP[0])));

/** First locator that matches, tried in order. */
async function find(scope, candidates) {{
  let last = null;
  for (const [kind, value] of candidates) {{
    const locator = kind === 'css' ? scope.locator(value)
                                   : scope.locator('xpath=' + value);
    try {{
      await locator.first().waitFor({{ state: 'attached', timeout: TIMEOUT }});
      return locator.first();
    }} catch (error) {{ last = error; }}
  }}
  throw new Error('no locator matched: ' + JSON.stringify(candidates) + ' ' + last);
}}

function frame(page, path) {{
  let scope = page;
  for (const index of path) scope = scope.frameLocator('iframe').nth(index);
  return scope;
}}

async function run(page) {{
"""

JS_FOOTER = """}

(async () => {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();
  try {
    await run(page);
    console.log('done');
  } finally {
    await browser.close();
  }
})();
"""


def script_to_javascript(script: Script) -> str:
    gap_min = script.gap_min_ms or 500
    gap_max = script.gap_max_ms or max(script.gap_min_ms or 500, 1500)
    variables = {v.name: ("" if v.secret else v.default) for v in script.variables}
    body: list[str] = []
    frame_now: list[int] = []
    scope = "page"

    if script.start_url and not (script.steps and script.steps[0].action == "goto"):
        body.append(f"  await page.goto({json.dumps(script.start_url)});")
        body.append("  await pause();")

    for step in script.steps:
        if not step.enabled:
            continue
        if step.frame_path != frame_now:
            frame_now = list(step.frame_path)
            if frame_now:
                body.append(f"  const scope = frame(page, {json.dumps(frame_now)});")
                scope = "scope"
            else:
                scope = "page"
        body.append(f"  // {step.describe()}")
        body.extend(_javascript_step(step, scope))
        body.append("  await pause();")

    header = JS_HEADER.format(
        name=script.name,
        description=script.description or "—",
        slug=(script.name or "script").replace(" ", "_"),
        gap_min=gap_min,
        gap_max=gap_max,
        variables=json.dumps(variables, ensure_ascii=False, indent=2),
    )
    return header + "\n".join(body) + "\n" + JS_FOOTER


def _javascript_step(step: Step, scope: str) -> list[str]:
    targets = json.dumps(_targets(step))
    value = step.value or ""
    action = step.action

    if action == "goto":
        return [f"  await page.goto({json.dumps(step.url or '')});"]
    if action == "wait":
        return [f"  await page.waitForTimeout({int(float(value or 0))});"]
    if action == "switch_window":
        return ["  // a new window: Playwright exposes it through context.pages()"]
    if action == "screenshot":
        return [
            f"  await page.screenshot({{ path: {json.dumps((value or 'shot') + '.png')} }});"
        ]
    if action == "scroll":
        return [f"  await page.mouse.wheel(0, {int(float(value or 0))});"]
    if action == "press_key":
        key = _js_key(value)
        if step.targets:
            return [f"  await (await find({scope}, {targets})).press({json.dumps(key)});"]
        return [f"  await page.keyboard.press({json.dumps(key)});"]
    if action == "assert_text":
        return [
            f"  {{ const text = await (await find({scope}, {targets})).innerText();",
            f"    if (!text.includes({json.dumps(value)})) "
            f"throw new Error('missing: ' + {json.dumps(value)}); }}",
        ]
    if action == "select":
        return [
            f"  await (await find({scope}, {targets})).selectOption("
            f"{{ label: {json.dumps(value)} }})"
            f".catch(() => (find({scope}, {targets}))"
            f".then((e) => e.selectOption({json.dumps(step.option_value or value)})));"
        ]
    if action == "type":
        name = _variable_name(value)
        source = f"VARIABLES[{json.dumps(name)}]" if name else json.dumps(value)
        return [f"  await (await find({scope}, {targets})).fill({source});"]
    if action == "hover":
        return [f"  await (await find({scope}, {targets})).hover();"]
    if action == "double_click":
        return [f"  await (await find({scope}, {targets})).dblclick();"]
    if action == "right_click":
        return [
            f"  await (await find({scope}, {targets})).click("
            f"{{ button: 'right' }});"
        ]
    return [f"  await (await find({scope}, {targets})).click();"]


_JS_KEYS = {
    "ENTER": "Enter", "ESCAPE": "Escape", "TAB": "Tab", "SPACE": " ",
    "BACKSPACE": "Backspace", "DELETE": "Delete", "ARROW_UP": "ArrowUp",
    "ARROW_DOWN": "ArrowDown", "ARROW_LEFT": "ArrowLeft",
    "ARROW_RIGHT": "ArrowRight", "HOME": "Home", "END": "End",
    "PAGE_UP": "PageUp", "PAGE_DOWN": "PageDown",
}


def _js_key(value: str) -> str:
    return _JS_KEYS.get((value or "ENTER").upper(), value or "Enter")
