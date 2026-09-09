"""Opt-in end-to-end check: record a real interaction, then replay it.

pytest does not pick this up (it opens a real browser). Run it by hand after
installing, to prove the whole loop works on this machine:

    .venv\\Scripts\\python.exe tests\\manual_e2e.py

By default it drives Microsoft Edge through `webscripts.driver`. Set
WEBSCRIPTS_E2E_HEADLESS=1 to run without a visible window.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from selenium.webdriver.common.by import By  # noqa: E402
from selenium.webdriver.support.ui import Select  # noqa: E402

from webscripts.driver import create_driver  # noqa: E402
from webscripts.human import Human  # noqa: E402
from webscripts.models import Script  # noqa: E402
from webscripts.player import Player  # noqa: E402
from webscripts.recorder import Recorder  # noqa: E402
from webscripts.session import _collect_variables  # noqa: E402

# The consent dialog exists on the first visit only — exactly like the cookie
# banner a site shows once. The replay must step over it instead of failing.
CONSENT = """
  <div id="consent">
    <p>دا پاڼه کوکیز کاروي.</p>
    <button id="accept-all">Accept all</button>
  </div>
  <script>
    document.getElementById('accept-all').onclick = function () {
      document.getElementById('consent').remove();
    };
  </script>
"""

PAGE = """<!doctype html>
<html lang="ps" dir="rtl"><head><meta charset="utf-8"><title>WebScripts demo</title></head>
<body>
  __CONSENT__
  <button id="menu-btn" aria-label="Menu">Menu</button>
  <div id="menu" style="display:none">
    <a href="#" data-testid="settings-link">تنظیمات</a>
  </div>
  <div id="panel" style="display:none">
    <input name="nick" placeholder="نوم">
    <select name="theme">
      <option value="light">رڼا</option>
      <option value="dark">تیاره</option>
    </select>
    <button id="save">خوندي کول</button>
  </div>
  <input type="password" id="pw_field">
  <iframe id="frame" srcdoc='<!doctype html><meta charset="utf-8"><body><button id="in-frame" data-testid="frame-btn">دننه تڼۍ</button><script>document.getElementById("in-frame").onclick=function(){this.textContent="ok";};</script></body>'></iframe>
  <div id="result"></div>
<script>
  document.getElementById('menu-btn').onclick = function () {
    document.getElementById('menu').style.display = 'block';
  };
  document.querySelector('[data-testid="settings-link"]').onclick = function (e) {
    e.preventDefault();
    document.getElementById('panel').style.display = 'block';
  };
  document.getElementById('save').onclick = function () {
    document.getElementById('result').textContent =
      'theme=' + document.querySelector('select[name=theme]').value +
      ';nick=' + document.querySelector('input[name=nick]').value;
  };
</script>
</body></html>
"""

EXPECTED = "theme=dark;nick=Elyas"


def main() -> int:
    headless = os.environ.get("WEBSCRIPTS_E2E_HEADLESS") == "1"
    page = Path(tempfile.gettempdir()) / "webscripts_demo.html"
    page.write_text(PAGE.replace("__CONSENT__", CONSENT), "utf-8")
    url = page.as_uri()

    # -- record ---------------------------------------------------------------
    # The recorder and this script share one driver, and the frame context is
    # global to a WebDriver session, so drain synchronously between actions:
    # `loop` with an always-true stop flag performs exactly one poll.
    driver = create_driver(headless=headless, use_profile=False)
    recorder = Recorder(driver, on_log=lambda level, msg: print(f"  [{level}] {msg}"))
    recorder.start(url)

    def tick() -> None:
        recorder.loop(lambda: True)

    tick()
    print("== simulating a user ==")
    driver.find_element(By.ID, "accept-all").click()
    tick()
    driver.find_element(By.ID, "menu-btn").click()
    tick()
    driver.find_element(By.CSS_SELECTOR, '[data-testid="settings-link"]').click()
    tick()
    nick = driver.find_element(By.CSS_SELECTOR, 'input[name="nick"]')
    nick.click()
    nick.send_keys("Elyas")
    tick()
    Select(
        driver.find_element(By.CSS_SELECTOR, 'select[name="theme"]')
    ).select_by_visible_text("تیاره")
    tick()
    password = driver.find_element(By.ID, "pw_field")
    password.click()
    password.send_keys("hunter2")
    driver.find_element(By.TAG_NAME, "body").click()  # blur flushes the field
    tick()
    driver.find_element(By.ID, "save").click()
    tick()
    driver.switch_to.frame(driver.find_element(By.ID, "frame"))
    driver.find_element(By.ID, "in-frame").click()
    driver.switch_to.default_content()
    tick()

    steps = recorder.steps
    driver.quit()

    print(f"\n== recorded {len(steps)} steps ==")
    for index, step in enumerate(steps, 1):
        locator = step.targets[0].value if step.targets else "-"
        print(f"  {index:>2}. {step.action:<10} {locator:<38} frame={step.frame_path}")

    script = Script(name="e2e", start_url=url, steps=steps)
    script.variables = _collect_variables(script.steps)

    # -- replay ---------------------------------------------------------------
    # Second visit: no consent dialog any more, and the run is humanised
    # (random gaps, random click points, the odd scroll).
    page.write_text(PAGE.replace("__CONSENT__", ""), "utf-8")
    driver = create_driver(headless=headless, use_profile=False)
    result = Player(
        driver,
        speed=2.0,
        step_timeout=8,
        human=Human(min_gap=0.2, max_gap=0.5, think_chance=0.0),
    ).play(script, {"password": "hunter2"})
    text = driver.find_element(By.ID, "result").text
    driver.switch_to.frame(driver.find_element(By.ID, "frame"))
    frame_text = driver.find_element(By.ID, "in-frame").text
    driver.switch_to.default_content()
    stored_password = driver.execute_script(
        "return document.getElementById('pw_field').value;"
    )
    driver.quit()

    print(f"\n== replay: {result}")
    print(f"== result element: {text!r}")
    print(f"== iframe button: {frame_text!r}   password field: {stored_password!r}")

    ok = (
        result["status"] == "ok"
        and result.get("skipped") == 1  # the consent click was stepped over
        and text == EXPECTED
        and frame_text == "ok"
        and stored_password == "hunter2"
        and any(v.name == "password" for v in script.variables)
        and all(not (s.secret and s.value not in (None, "{{password}}")) for s in steps)
    )
    print("\nE2E:", "PASS" if ok else f"FAIL (expected {EXPECTED!r})")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
