"""Human-like timing and pointer behaviour for replay.

A script that clicks the exact centre of every button, always waits the same
number of milliseconds and never scrolls looks nothing like a person, and that
pattern is exactly what the big sites fingerprint. Everything here exists to
break that pattern while keeping the run reliable.

The numbers follow what the user asked for: 0.5–1.5 s between actions, a
random point inside the widget instead of its centre, and the occasional small
scroll along the way.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field


@dataclass
class Human:
    """Random-but-plausible timing for one run."""

    enabled: bool = True
    min_gap: float = 0.5
    max_gap: float = 1.5
    # Roughly one action in six is followed by a longer "reading" pause.
    think_chance: float = 0.16
    think_gap: tuple[float, float] = (1.8, 3.6)
    # How often an action is preceded by a little scrolling.
    scroll_chance: float = 0.22
    scroll_range: tuple[int, int] = (80, 320)
    # Typing speed per character, in seconds.
    key_delay: tuple[float, float] = (0.045, 0.16)
    seed: int | None = None
    rng: random.Random = field(init=False)

    def __post_init__(self) -> None:
        self.rng = random.Random(self.seed)
        self.min_gap = max(0.0, float(self.min_gap))
        self.max_gap = max(self.min_gap, float(self.max_gap))

    # ------------------------------------------------------------- timing

    def gap(self, base: float = 0.0) -> float:
        """How long to wait before the next action.

        `base` is the pause the person actually took while recording; the
        result is never shorter than the random gap, so a fast recording does
        not turn into a machine-gun replay.
        """
        if not self.enabled:
            return base
        wait = max(base, self.rng.uniform(self.min_gap, self.max_gap))
        if self.rng.random() < self.think_chance:
            wait += self.rng.uniform(*self.think_gap)
        return wait

    def key_gap(self) -> float:
        """Delay between two typed characters."""
        if not self.enabled:
            return 0.0
        delay = self.rng.uniform(*self.key_delay)
        # People stumble: now and then a character takes noticeably longer.
        if self.rng.random() < 0.06:
            delay += self.rng.uniform(0.15, 0.4)
        return delay

    # ------------------------------------------------------------ pointer

    def offset(self, width: float, height: float) -> tuple[int, int]:
        """A random point inside the widget, given as an offset from its centre.

        The point stays in the middle 60% of the box, so a padded button is
        still hit on its label and never on the 1-pixel border.
        """
        if not self.enabled:
            return (0, 0)
        return (self._axis(width), self._axis(height))

    def _axis(self, size: float) -> int:
        span = (float(size or 0) / 2.0) * 0.6
        if span < 2:
            return 0
        return int(self.rng.uniform(-span, span))

    # ------------------------------------------------------------- scroll

    def should_scroll(self) -> bool:
        return self.enabled and self.rng.random() < self.scroll_chance

    def scroll_amount(self) -> int:
        """Pixels to scroll, usually down and sometimes back up a little."""
        amount = self.rng.randint(*self.scroll_range)
        return -int(amount * 0.4) if self.rng.random() < 0.3 else amount


def from_settings(settings) -> Human | None:
    """Build the Human for a run, or None when the user turned it off."""
    if not getattr(settings, "humanize", False):
        return None
    return Human(
        min_gap=getattr(settings, "human_min_gap", 0.5),
        max_gap=getattr(settings, "human_max_gap", 1.5),
        scroll_chance=0.22 if getattr(settings, "random_scroll", True) else 0.0,
    )
