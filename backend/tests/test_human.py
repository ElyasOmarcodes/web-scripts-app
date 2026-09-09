"""The random-but-plausible behaviour that keeps accounts out of trouble."""

from __future__ import annotations

from webscripts.human import Human, from_settings
from webscripts.settings import Settings


def test_gaps_stay_inside_the_asked_for_range():
    human = Human(min_gap=0.5, max_gap=1.5, think_chance=0.0, seed=7)

    gaps = [human.gap() for _ in range(200)]

    assert all(0.5 <= g <= 1.5 for g in gaps)
    # Random, not a constant.
    assert len(set(gaps)) > 100


def test_a_gap_is_never_shorter_than_the_recorded_pause():
    human = Human(min_gap=0.5, max_gap=1.5, think_chance=0.0, seed=1)

    assert human.gap(2.5) >= 2.5


def test_thinking_pauses_happen_sometimes():
    human = Human(min_gap=0.0, max_gap=0.0, think_chance=1.0, seed=3)

    assert human.gap() >= 1.8


def test_click_points_land_inside_the_widget_but_off_centre():
    human = Human(seed=11)

    points = [human.offset(200, 40) for _ in range(100)]

    assert all(abs(x) <= 60 and abs(y) <= 12 for x, y in points)
    assert any(x != 0 or y != 0 for x, y in points)


def test_tiny_widgets_are_clicked_in_the_middle():
    assert Human(seed=2).offset(6, 5) == (0, 0)


def test_disabled_human_is_a_no_op():
    human = Human(enabled=False, min_gap=0.5, max_gap=1.5)

    assert human.gap(0.3) == 0.3
    assert human.offset(300, 80) == (0, 0)
    assert human.key_gap() == 0.0
    assert not human.should_scroll()


def test_scrolling_goes_both_ways():
    human = Human(seed=5)

    amounts = [human.scroll_amount() for _ in range(200)]

    assert any(a > 0 for a in amounts) and any(a < 0 for a in amounts)


def test_settings_switch_the_behaviour_off():
    assert from_settings(Settings(humanize=False)) is None
    human = from_settings(Settings(human_min_gap=0.8, human_max_gap=2.0))
    assert human is not None and (human.min_gap, human.max_gap) == (0.8, 2.0)


def test_random_scroll_can_be_turned_off_on_its_own():
    human = from_settings(Settings(random_scroll=False))

    assert human is not None and not human.should_scroll()
