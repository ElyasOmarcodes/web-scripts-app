"""JSON file storage for scripts (one file per script)."""

from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path

from . import config
from .models import Script

_SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class StorageError(RuntimeError):
    pass


class Storage:
    def __init__(self, directory: Path | None = None) -> None:
        self.dir = Path(directory) if directory else config.SCRIPTS_DIR
        self.dir.mkdir(parents=True, exist_ok=True)

    def _path(self, script_id: str) -> Path:
        if not _SAFE_ID.match(script_id):
            raise StorageError(f"invalid script id: {script_id!r}")
        return self.dir / f"{script_id}.json"

    def list(self) -> list[Script]:
        scripts: list[Script] = []
        for path in sorted(self.dir.glob("*.json")):
            try:
                scripts.append(Script.model_validate_json(path.read_text("utf-8")))
            except Exception:
                # A corrupt file must not take the whole list down.
                continue
        scripts.sort(key=lambda s: s.updated_at, reverse=True)
        return scripts

    def get(self, script_id: str) -> Script | None:
        path = self._path(script_id)
        if not path.exists():
            return None
        return Script.model_validate_json(path.read_text("utf-8"))

    def save(self, script: Script) -> Script:
        script.touch()
        path = self._path(script.id)
        data = json.dumps(script.model_dump(), ensure_ascii=False, indent=2)
        # Atomic write so an interrupted save never truncates an old script.
        fd, tmp = tempfile.mkstemp(dir=str(self.dir), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        return script

    def delete(self, script_id: str) -> bool:
        path = self._path(script_id)
        if path.exists():
            path.unlink()
            return True
        return False

    def export(self, script_id: str, dest: Path) -> Path:
        script = self.get(script_id)
        if script is None:
            raise StorageError(f"script not found: {script_id}")
        dest = Path(dest)
        dest.write_text(
            json.dumps(script.model_dump(), ensure_ascii=False, indent=2), "utf-8"
        )
        return dest

    def import_file(self, source: Path, new_id: bool = True) -> Script:
        script = Script.model_validate_json(Path(source).read_text("utf-8"))
        if new_id or self.get(script.id) is not None:
            from .models import new_id as make_id

            script.id = make_id("scr")
        return self.save(script)
