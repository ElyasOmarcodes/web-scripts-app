"""Data model for recorded scripts.

A script is an ordered list of steps. Every step that touches the page keeps
several *targets* (locator candidates ordered from most to least robust); the
player tries them in order, which is what makes replay survive small layout
changes on sites like Facebook.
"""

from __future__ import annotations

import time
import uuid
from typing import Any, Literal

from pydantic import BaseModel, Field

Action = Literal[
    "goto",
    "click",
    "double_click",
    "right_click",
    "type",
    "select",
    "press_key",
    "hover",
    "scroll",
    "wait",
    "switch_window",
    "assert_text",
    "screenshot",
]

KEYS = {
    "ENTER",
    "ESCAPE",
    "TAB",
    "SPACE",
    "BACKSPACE",
    "DELETE",
    "ARROW_UP",
    "ARROW_DOWN",
    "ARROW_LEFT",
    "ARROW_RIGHT",
    "HOME",
    "END",
    "PAGE_UP",
    "PAGE_DOWN",
}


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def now_ms() -> int:
    return int(time.time() * 1000)


class Target(BaseModel):
    """One locator candidate for an element."""

    type: Literal["css", "xpath"] = "css"
    value: str
    # Where the locator came from: testid, id, name, aria, placeholder, text,
    # link, path... Used only for display and debugging.
    kind: str = "generic"


class Step(BaseModel):
    id: str = Field(default_factory=lambda: new_id("stp"))
    action: Action
    targets: list[Target] = Field(default_factory=list)
    # Text to type, option to select, key name, URL fragment to assert...
    value: str | None = None
    # For <select>: the underlying option value, tried when the visible text
    # does not match (translated UI, changed label).
    option_value: str | None = None
    url: str | None = None
    # Index path of nested iframes, empty for the main document.
    frame_path: list[int] = Field(default_factory=list)
    label: str = ""
    tag: str | None = None
    # Pause (ms) recorded between the previous step and this one.
    delay_ms: int = 0
    enabled: bool = True
    # "Skip me when my element is not there": cookie dialogs, one-off banners.
    # Left unset, the player decides for itself (see Player._should_skip).
    optional: bool = False
    # A password field: the value is never stored, a variable is used instead.
    secret: bool = False
    ts: int = 0
    note: str = ""

    def describe(self) -> str:
        """Short human readable line used in logs and in the UI."""
        what = self.label or (self.targets[0].value if self.targets else "")
        if self.action == "goto":
            return f"پرانیستل: {self.url}"
        if self.action == "click":
            return f"کلیک: {what}"
        if self.action == "double_click":
            return f"دوه ځله کلیک: {what}"
        if self.action == "right_click":
            return f"ښي کلیک: {what}"
        if self.action == "type":
            shown = "••••••" if self.secret else (self.value or "")
            return f"لیکل «{shown}» په: {what}"
        if self.action == "select":
            return f"غوره کول «{self.value}» له: {what}"
        if self.action == "press_key":
            return f"تڼۍ: {self.value}"
        if self.action == "hover":
            return f"موږک پورته: {what}"
        if self.action == "scroll":
            return f"سکرول: {self.value}"
        if self.action == "wait":
            return f"انتظار: {self.value} ms"
        if self.action == "switch_window":
            return "بلې کړکۍ ته تګ"
        if self.action == "assert_text":
            return f"د متن کتنه: {self.value}"
        if self.action == "screenshot":
            return "عکس اخیستل"
        return self.action


class Variable(BaseModel):
    name: str
    label: str = ""
    secret: bool = False
    default: str = ""


class Script(BaseModel):
    id: str = Field(default_factory=lambda: new_id("scr"))
    name: str = "بې نومه سکریپټ"
    description: str = ""
    start_url: str = ""
    steps: list[Step] = Field(default_factory=list)
    variables: list[Variable] = Field(default_factory=list)
    created_at: int = Field(default_factory=now_ms)
    updated_at: int = Field(default_factory=now_ms)
    last_run_at: int | None = None
    last_run_ok: bool | None = None

    def touch(self) -> None:
        self.updated_at = now_ms()

    def summary(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "start_url": self.start_url,
            "step_count": len([s for s in self.steps if s.enabled]),
            "total_steps": len(self.steps),
            "variables": [v.model_dump() for v in self.variables],
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "last_run_at": self.last_run_at,
            "last_run_ok": self.last_run_ok,
        }
