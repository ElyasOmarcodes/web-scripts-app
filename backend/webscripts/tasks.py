"""Tasks: one script, run over a set of accounts, remembered between runs.

A script says *what to do*; a task says *who to do it as*. Running the same
script for three X accounts is one task with three account runs, and the task
remembers how each of them went — so a run that stopped half way can be picked
up from the account it stopped at instead of starting over.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Iterable

from pydantic import BaseModel, Field

from . import config
from .models import new_id

# What one account's run ended as.
PENDING = "pending"
RUNNING = "running"
OK = "ok"
FAILED = "failed"
STOPPED = "stopped"

# What the whole task ended as. "partial" is the yellow one: some accounts are
# done, some never ran.
DRAFT = "draft"
DONE = "done"
PARTIAL = "partial"


class AccountRun(BaseModel):
    """How one account's turn went."""

    account_id: str
    status: str = PENDING
    started_at: int | None = None
    finished_at: int | None = None
    completed: int = 0
    total: int = 0
    error: str | None = None
    screenshot: str | None = None

    @property
    def finished_well(self) -> bool:
        return self.status == OK


class Task(BaseModel):
    id: str = Field(default_factory=lambda: new_id("tsk"))
    name: str = "نوی کار"
    script_id: str = ""
    # Which accounts this task runs as, in this order.
    account_ids: list[str] = Field(default_factory=list)
    # How many browser windows work at the same time; they are tiled so the
    # user can watch all of them at once. The ceiling is the machine's, not
    # ours — webscripts/machine.py works out what a number will cost.
    concurrency: int = Field(default=1, ge=1, le=32)
    # Run options, each falling back to Settings when unset.
    browser: str | None = None
    speed: float | None = None
    headless: bool | None = None
    keep_open: bool = False
    # Stop the whole task at the first account that fails, or carry on.
    stop_on_error: bool = False
    # Wait this long between two accounts, so a burst does not look like one.
    gap_seconds: float = Field(default=3.0, ge=0.0, le=600.0)
    variables: dict[str, str] = Field(default_factory=dict)
    note: str = ""

    status: str = DRAFT
    runs: list[AccountRun] = Field(default_factory=list)
    created_at: int = Field(default_factory=lambda: int(time.time() * 1000))
    updated_at: int = Field(default_factory=lambda: int(time.time() * 1000))
    last_run_at: int | None = None

    # ------------------------------------------------------------- helpers

    def touch(self) -> None:
        self.updated_at = int(time.time() * 1000)

    def run_for(self, account_id: str) -> AccountRun:
        for run in self.runs:
            if run.account_id == account_id:
                return run
        run = AccountRun(account_id=account_id)
        self.runs.append(run)
        return run

    def sync_runs(self) -> None:
        """Keep one run row per selected account, in the selected order."""
        by_id = {r.account_id: r for r in self.runs}
        self.runs = [
            by_id.get(account_id) or AccountRun(account_id=account_id)
            for account_id in self.account_ids
        ]

    def pending_accounts(self) -> list[str]:
        """Accounts that still have work to do — what "resume" runs."""
        self.sync_runs()
        return [r.account_id for r in self.runs if not r.finished_well]

    def can_resume(self) -> bool:
        return self.status in {PARTIAL, FAILED} and bool(self.pending_accounts())

    def reset_runs(self, account_ids: Iterable[str] | None = None) -> None:
        wanted = set(account_ids) if account_ids is not None else None
        self.sync_runs()
        for run in self.runs:
            if wanted is None or run.account_id in wanted:
                run.status = PENDING
                run.started_at = None
                run.finished_at = None
                run.completed = 0
                run.total = 0
                run.error = None
                run.screenshot = None

    def settle(self) -> str:
        """Work out the task's colour from the account runs."""
        self.sync_runs()
        if not self.runs:
            self.status = DRAFT
            return self.status
        states = {r.status for r in self.runs}
        if states == {OK}:
            self.status = DONE
        elif FAILED in states and not (states & {PENDING, RUNNING, STOPPED}):
            # Everything ran, and at least one failed.
            self.status = FAILED if OK not in states else PARTIAL
        elif states & {PENDING, RUNNING, STOPPED}:
            # Something never ran (stopped, or cut short) — the yellow case.
            self.status = PARTIAL if (states & {OK, FAILED}) else DRAFT
        else:
            self.status = PARTIAL
        return self.status

    def summary(self) -> dict:
        self.sync_runs()
        return {
            **self.model_dump(),
            "done_count": sum(1 for r in self.runs if r.finished_well),
            "failed_count": sum(1 for r in self.runs if r.status == FAILED),
            "pending_count": len(self.pending_accounts()),
        }


class TaskStore:
    """All tasks in one file — there are never many, and order matters."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else config.BASE_DIR / "tasks.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._tasks: list[Task] | None = None

    # ----------------------------------------------------------- storage

    def _load(self) -> list[Task]:
        if self._tasks is not None:
            return self._tasks
        tasks: list[Task] = []
        if self.path.exists():
            try:
                raw = json.loads(self.path.read_text("utf-8"))
                for item in raw.get("tasks", []):
                    try:
                        tasks.append(Task.model_validate(item))
                    except Exception:  # noqa: BLE001 - skip a broken row only
                        continue
            except Exception:  # noqa: BLE001 - a corrupt file starts empty
                tasks = []
        self._tasks = tasks
        return tasks

    def _save(self) -> None:
        data = {"tasks": [t.model_dump() for t in self._load()]}
        text = json.dumps(data, ensure_ascii=False, indent=2)
        fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
            os.replace(tmp, self.path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # ------------------------------------------------------------- crud

    def list(self) -> list[Task]:
        return sorted(self._load(), key=lambda t: t.updated_at, reverse=True)

    def get(self, task_id: str) -> Task | None:
        for task in self._load():
            if task.id == task_id:
                return task
        return None

    def create(self, **fields) -> Task:
        task = Task(**fields)
        task.sync_runs()
        self._load().append(task)
        self._save()
        return task

    def update(self, task_id: str, **changes) -> Task | None:
        task = self.get(task_id)
        if task is None:
            return None
        for key, value in changes.items():
            if value is None or not hasattr(task, key):
                continue
            setattr(task, key, value)
        task.sync_runs()
        task.settle()
        task.touch()
        self._save()
        return task

    def save(self, task: Task) -> Task:
        task.touch()
        tasks = self._load()
        for index, existing in enumerate(tasks):
            if existing.id == task.id:
                tasks[index] = task
                break
        else:
            tasks.append(task)
        self._save()
        return task

    def delete(self, task_id: str) -> bool:
        tasks = self._load()
        remaining = [t for t in tasks if t.id != task_id]
        if len(remaining) == len(tasks):
            return False
        self._tasks = remaining
        self._save()
        self.clear_log(task_id)
        return True

    def forget_account(self, account_id: str) -> None:
        """A deleted account must not linger in any task."""
        changed = False
        for task in self._load():
            if account_id in task.account_ids:
                task.account_ids = [a for a in task.account_ids if a != account_id]
                task.sync_runs()
                task.settle()
                changed = True
        if changed:
            self._save()

    def forget_script(self, script_id: str) -> None:
        """A deleted script leaves its tasks without one, not pointing at air."""
        changed = False
        for task in self._load():
            if task.script_id == script_id:
                task.script_id = ""
                changed = True
        if changed:
            self._save()

    # ------------------------------------------------------------- log

    def log_path(self, task_id: str) -> Path:
        """Where one task's own log lives, separate from the shared stream."""
        directory = self.path.parent / "task-logs"
        directory.mkdir(parents=True, exist_ok=True)
        safe = "".join(c for c in task_id if c.isalnum() or c in "_-")[:64]
        return directory / f"{safe or 'task'}.jsonl"

    def append_log(self, task_id: str, entry: dict) -> None:
        """One line per event. The file is trimmed when it grows too long."""
        path = self.log_path(task_id)
        try:
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            return
        if path.stat().st_size > 512_000:
            self._trim_log(path)

    def _trim_log(self, path: Path, keep: int = 600) -> None:
        try:
            lines = path.read_text("utf-8").splitlines()[-keep:]
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        except OSError:
            pass

    def read_log(self, task_id: str, limit: int = 400) -> list[dict]:
        path = self.log_path(task_id)
        if not path.exists():
            return []
        entries: list[dict] = []
        try:
            for line in path.read_text("utf-8").splitlines()[-limit:]:
                try:
                    entries.append(json.loads(line))
                except ValueError:
                    continue
        except OSError:
            return []
        return entries

    def clear_log(self, task_id: str) -> None:
        path = self.log_path(task_id)
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass

    def overview(self) -> dict:
        tasks = self._load()
        return {
            "total": len(tasks),
            "done": sum(1 for t in tasks if t.status == DONE),
            "failed": sum(1 for t in tasks if t.status == FAILED),
            "partial": sum(1 for t in tasks if t.status == PARTIAL),
            "running": sum(1 for t in tasks if t.status == RUNNING),
            "draft": sum(1 for t in tasks if t.status == DRAFT),
        }
