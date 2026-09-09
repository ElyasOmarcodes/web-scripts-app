"""User preferences, stored next to the scripts as settings.json."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field

from . import config


class Settings(BaseModel):
    # "auto" lets the backend pick Edge, then Chrome, then any Chromium browser.
    browser: str = "auto"
    headless: bool = False
    keep_open: bool = False
    speed: float = Field(default=1.0, ge=0.25, le=8.0)
    capture_scroll: bool = False
    step_timeout: float = Field(default=15.0, ge=3.0, le=120.0)
    # Reuse a dedicated browser profile so logins survive between runs.
    use_profile: bool = True
    # Anti-ban behaviour: random pauses, random click points, random scrolling.
    humanize: bool = True
    human_min_gap: float = Field(default=0.5, ge=0.0, le=10.0)
    human_max_gap: float = Field(default=1.5, ge=0.0, le=20.0)
    random_scroll: bool = True
    # Let a run continue when a step's element is legitimately gone (a cookie
    # dialog that only appears once, a banner already dismissed, …).
    smart_skip: bool = True
    theme: Literal["system", "light", "dark"] = "system"
    accent: str = "blue"
    sidebar_collapsed: bool = False
    confirm_delete: bool = True


class SettingsStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else config.BASE_DIR / "settings.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._cache: Settings | None = None

    def load(self) -> Settings:
        if self._cache is not None:
            return self._cache
        if self.path.exists():
            try:
                self._cache = Settings.model_validate_json(
                    self.path.read_text("utf-8")
                )
                return self._cache
            except Exception:  # noqa: BLE001 - fall back to defaults
                pass
        self._cache = Settings()
        return self._cache

    def save(self, settings: Settings) -> Settings:
        data = json.dumps(settings.model_dump(), ensure_ascii=False, indent=2)
        fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
            os.replace(tmp, self.path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        self._cache = settings
        return settings

    def update(self, changes: dict) -> Settings:
        merged = self.load().model_dump()
        merged.update({k: v for k, v in changes.items() if v is not None})
        return self.save(Settings.model_validate(merged))
