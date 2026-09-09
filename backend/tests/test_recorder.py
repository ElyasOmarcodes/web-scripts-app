"""Recorder tests: raw browser events in, clean steps out."""

from __future__ import annotations

from webscripts.models import Step
from webscripts.recorder import Recorder
from webscripts.session import _collect_variables


def make_recorder() -> Recorder:
    return Recorder(driver=None)


def event(action: str, **kwargs) -> dict:
    base = {
        "action": action,
        "ts": kwargs.pop("ts", 1_000),
        "url": "https://facebook.com",
        "targets": kwargs.pop("targets", [{"type": "css", "value": "#x", "kind": "id"}]),
        "label": kwargs.pop("label", "دکمه"),
        "tag": "button",
    }
    base.update(kwargs)
    return base


def test_click_event_becomes_step():
    recorder = make_recorder()
    step = recorder._to_step(event("click"))

    assert step is not None
    assert step.action == "click"
    assert step.targets[0].value == "#x"
    assert step.label == "دکمه"


def test_event_without_targets_is_dropped():
    assert make_recorder()._to_step(event("click", targets=[])) is None


def test_unknown_action_is_dropped():
    assert make_recorder()._to_step(event("mousemove")) is None


def test_password_value_is_not_stored():
    step = make_recorder()._to_step(event("type", value="hunter2", secret=True))

    assert step is not None
    assert step.secret is True
    assert step.value is None


def test_select_keeps_option_value():
    step = make_recorder()._to_step(
        event("select", value="تیاره", optionValue="dark", tag="select")
    )

    assert step is not None
    assert step.value == "تیاره"
    assert step.option_value == "dark"


def test_delay_between_steps_is_measured():
    recorder = make_recorder()
    recorder._append(Step(action="click", ts=1_000))
    recorder._append(Step(action="click", ts=2_500))

    assert recorder.steps[1].delay_ms == 1_500


def test_delay_is_capped():
    recorder = make_recorder()
    recorder._append(Step(action="click", ts=1_000))
    recorder._append(Step(action="click", ts=1_000_000))

    assert recorder.steps[1].delay_ms == 8_000


def test_duplicate_fast_clicks_are_collapsed():
    from webscripts.models import Target

    recorder = make_recorder()
    targets = [Target(type="css", value="#same")]
    recorder._append(Step(action="click", targets=targets, ts=1_000))
    recorder._append(Step(action="click", targets=list(targets), ts=1_100))

    assert len(recorder.steps) == 1


def test_redirect_chain_keeps_final_url():
    recorder = make_recorder()
    recorder._append(Step(action="goto", url="https://a.test", ts=1_000))
    recorder._append(Step(action="goto", url="https://b.test", ts=1_200))

    assert len(recorder.steps) == 1
    assert recorder.steps[0].url == "https://b.test"


def test_frame_path_is_kept():
    step = make_recorder()._to_step(event("click", frame_path=[1, 0]))
    assert step is not None
    assert step.frame_path == [1, 0]


def test_collect_variables_names_secrets():
    steps = [
        Step(action="type", secret=True, label="Password"),
        Step(action="type", secret=True, label="Confirm"),
        Step(action="click"),
    ]

    variables = _collect_variables(steps)

    assert [v.name for v in variables] == ["password", "password_2"]
    assert steps[0].value == "{{password}}"
    assert steps[1].value == "{{password_2}}"
    assert all(v.secret for v in variables)
