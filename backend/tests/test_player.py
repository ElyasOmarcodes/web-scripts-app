"""Player tests driven by a fake WebDriver — no browser required."""

from __future__ import annotations

from webscripts.models import Script, Step, Target
from webscripts.player import Player


class FakeElement:
    def __init__(self, name: str, displayed: bool = True) -> None:
        self.name = name
        self.displayed = displayed
        self.clicks = 0
        self.keys: list = []

    def is_displayed(self) -> bool:
        return self.displayed

    def click(self) -> None:
        self.clicks += 1

    def send_keys(self, *args) -> None:
        self.keys.append(args if len(args) > 1 else args[0])


class FakeSwitch:
    def __init__(self, driver) -> None:
        self.driver = driver

    def default_content(self) -> None:
        self.driver.frame_path = []

    def frame(self, index) -> None:
        self.driver.frame_path.append(index)
        self.driver.entered_frames.append(list(self.driver.frame_path))

    def parent_frame(self) -> None:
        if self.driver.frame_path:
            self.driver.frame_path.pop()

    def window(self, handle) -> None:
        self.driver.current_handle = handle


class FakeDriver:
    """Resolves locators from a dict of {locator: FakeElement}."""

    def __init__(self, elements: dict[str, FakeElement] | None = None) -> None:
        self.elements = elements or {}
        self.frame_path: list = []
        self.entered_frames: list[list] = []
        self.visited: list[str] = []
        self.scripts: list[str] = []
        self.window_handles = ["w1"]
        self.current_handle = "w1"
        self.switch_to = FakeSwitch(self)
        self.body_text = ""

    def find_elements(self, by, value):
        element = self.elements.get(value)
        return [element] if element else []

    def get(self, url: str) -> None:
        self.visited.append(url)

    def execute_script(self, script: str, *args):
        self.scripts.append(script)
        if "readyState" in script:
            return "complete"
        if "document.body" in script:
            return self.body_text
        if "arguments[0].click()" in script and args:
            args[0].clicks += 1
        return None

    def save_screenshot(self, path: str) -> bool:
        return True


def script_with(*steps: Step) -> Script:
    return Script(name="t", steps=list(steps))


def css(value: str) -> list[Target]:
    return [Target(type="css", value=value, kind="test")]


def test_click_uses_native_click():
    button = FakeElement("button")
    driver = FakeDriver({"#save": button})
    player = Player(driver)

    result = player.play(script_with(Step(action="click", targets=css("#save"))))

    assert result["status"] == "ok"
    assert result["completed"] == 1
    assert button.clicks == 1


def test_click_falls_back_to_javascript():
    from selenium.common.exceptions import ElementClickInterceptedException

    class Intercepted(FakeElement):
        def click(self):
            raise ElementClickInterceptedException("covered by overlay")

    button = Intercepted("button")
    driver = FakeDriver({"#save": button})

    result = Player(driver).play(script_with(Step(action="click", targets=css("#save"))))

    assert result["status"] == "ok"
    assert button.clicks == 1  # incremented by the JS fallback


def test_targets_are_tried_in_order():
    element = FakeElement("input")
    driver = FakeDriver({"#stable": element})
    step = Step(
        action="click",
        targets=[
            Target(type="css", value="#missing", kind="id"),
            Target(type="css", value="#stable", kind="path"),
        ],
    )

    assert Player(driver).play(script_with(step))["status"] == "ok"


def test_type_expands_variables():
    field = FakeElement("input")
    driver = FakeDriver({"#q": field})
    step = Step(action="type", targets=css("#q"), value="سلام {{user}}")

    Player(driver).play(script_with(step), {"user": "الیاس"})

    assert field.keys[-1] == "سلام الیاس"


def test_secret_step_reads_from_variables():
    field = FakeElement("input")
    driver = FakeDriver({"#pw": field})
    step = Step(action="type", targets=css("#pw"), value="{{password}}", secret=True)

    Player(driver).play(script_with(step), {"password": "s3cret"})

    assert field.keys[-1] == "s3cret"


def test_secret_step_without_value_fails():
    driver = FakeDriver({"#pw": FakeElement("input")})
    step = Step(action="type", targets=css("#pw"), value="{{password}}", secret=True)

    result = Player(driver).play(script_with(step))

    assert result["status"] == "failed"
    assert "password" in result["error"]


def test_missing_element_fails_with_label():
    driver = FakeDriver({})
    step = Step(action="click", targets=css("#gone"), label="تنظیمات")

    result = Player(driver, step_timeout=0.2).play(script_with(step))

    assert result["status"] == "failed"
    assert result["failed_index"] == 0
    assert "تنظیمات" in result["error"]


def test_disabled_steps_are_skipped():
    element = FakeElement("a")
    driver = FakeDriver({"#one": element})
    result = Player(driver).play(
        script_with(
            Step(action="click", targets=css("#one")),
            Step(action="click", targets=css("#two"), enabled=False),
        )
    )

    assert result["total"] == 1
    assert result["status"] == "ok"


def test_goto_navigates():
    driver = FakeDriver()
    result = Player(driver).play(script_with(Step(action="goto", url="https://x.test")))

    assert driver.visited == ["https://x.test"]
    assert result["status"] == "ok"


def test_frame_path_is_entered():
    element = FakeElement("btn")
    driver = FakeDriver({"#inner": element})
    step = Step(action="click", targets=css("#inner"), frame_path=[0, 2])

    Player(driver).play(script_with(step))

    assert [0, 2] in driver.entered_frames


def test_run_returns_to_the_top_document():
    """A run that ends inside an iframe must not leave the session there."""
    driver = FakeDriver({"#inner": FakeElement("btn")})
    step = Step(action="click", targets=css("#inner"), frame_path=[1])

    Player(driver).play(script_with(step))

    assert driver.frame_path == []


def test_assert_text_checks_page():
    driver = FakeDriver()
    driver.body_text = "تنظیمات بدل شول"

    ok = Player(driver).play(script_with(Step(action="assert_text", value="تنظیمات")))
    bad = Player(driver).play(script_with(Step(action="assert_text", value="نشته")))

    assert ok["status"] == "ok"
    assert bad["status"] == "failed"


def test_stop_flag_halts_run():
    driver = FakeDriver({"#a": FakeElement("a"), "#b": FakeElement("b")})
    calls = {"n": 0}

    def should_stop() -> bool:
        calls["n"] += 1
        return calls["n"] > 1

    result = Player(driver, should_stop=should_stop).play(
        script_with(
            Step(action="click", targets=css("#a")),
            Step(action="click", targets=css("#b")),
        )
    )

    assert result["status"] == "stopped"
    assert result["completed"] == 1


def test_press_key_rejects_unknown_key():
    driver = FakeDriver({"#a": FakeElement("a")})
    result = Player(driver).play(
        script_with(Step(action="press_key", targets=css("#a"), value="F13"))
    )
    assert result["status"] == "failed"


def test_progress_events_are_emitted():
    events: list[dict] = []
    driver = FakeDriver({"#a": FakeElement("a")})

    Player(driver, on_event=events.append).play(
        script_with(Step(action="click", targets=css("#a"), label="کلي"))
    )

    kinds = [e["type"] for e in events]
    assert kinds == ["step_start", "step_done"]
