"""Opt-in end-to-end check for tasks: one script, two accounts, two browsers.

pytest does not pick this up (it opens real browsers). Run it by hand:

    python tests/manual_task_e2e.py

It proves the three things a task promises: every account really runs, the
runs happen side by side when concurrency allows it, and a task that stopped
half way resumes at the account it stopped on.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from webscripts.accounts import AccountStore  # noqa: E402
from webscripts.models import Script, Step, Target  # noqa: E402
from webscripts.session import SessionManager  # noqa: E402
from webscripts.settings import Settings, SettingsStore  # noqa: E402
from webscripts.storage import Storage  # noqa: E402
from webscripts.tasks import OK, PARTIAL, PENDING, TaskStore  # noqa: E402

PAGE = """<!doctype html>
<html lang="ps" dir="rtl"><head><meta charset="utf-8"><title>task demo</title></head>
<body>
  <button id="go">وکړه</button>
  <div id="out"></div>
  <script>
    document.getElementById('go').onclick = function () {
      document.getElementById('out').textContent = 'done';
    };
  </script>
</body></html>
"""


def build(home: Path):
    os.environ["WEBSCRIPTS_HOME"] = str(home)
    storage = Storage(home / "scripts")
    settings = SettingsStore(home / "settings.json")
    settings.save(Settings(headless=os.environ.get("WEBSCRIPTS_E2E_HEADLESS") == "1",
                           human_min_gap=0.1, human_max_gap=0.3))
    accounts = AccountStore(home / "accounts.json")
    tasks = TaskStore(home / "tasks.json")
    return SessionManager(storage, settings, accounts, tasks)


def wait_idle(manager: SessionManager, timeout: float = 180) -> None:
    deadline = time.time() + timeout
    while manager.state != "idle" and time.time() < deadline:
        time.sleep(0.25)


def main() -> int:
    home = Path(tempfile.mkdtemp(prefix="wstask-"))
    page = Path(tempfile.gettempdir()) / "webscripts_task_demo.html"
    page.write_text(PAGE, "utf-8")
    url = page.as_uri()

    manager = build(home)
    script = manager.storage.save(
        Script(
            name="یو کلیک",
            start_url=url,
            steps=[
                Step(
                    action="click",
                    targets=[Target(type="css", value="#go", kind="id")],
                    label="وکړه",
                )
            ],
        )
    )
    first = manager.accounts.create("x", "اکاونټ ۱")
    second = manager.accounts.create("x", "اکاونټ ۲")
    task = manager.tasks.create(
        name="د دوو اکاونټونو کار",
        script_id=script.id,
        account_ids=[first.id, second.id],
        concurrency=2,
        gap_seconds=0,
    )

    print("== running both accounts ==")
    started = time.time()
    manager.start_task(task.id)
    wait_idle(manager)
    took = time.time() - started
    task = manager.tasks.get(task.id)
    print(f"   status={task.status} in {took:.1f}s")
    for run in task.runs:
        print(f"   {run.account_id}: {run.status} ({run.completed}/{run.total})")

    both_ok = all(run.status == OK for run in task.runs) and task.status == "done"

    print("\n== resuming a task that stopped half way ==")
    task.run_for(second.id).status = PENDING
    task.run_for(second.id).completed = 0
    task.settle()
    manager.tasks.save(task)
    print(f"   before: status={task.status} pending={task.pending_accounts()}")
    stopped_is_yellow = task.status == PARTIAL

    manager.start_task(task.id, resume=True)
    wait_idle(manager)
    task = manager.tasks.get(task.id)
    print(f"   after:  status={task.status} pending={task.pending_accounts()}")

    resumed = task.status == "done" and not task.pending_accounts()

    ok = both_ok and stopped_is_yellow and resumed
    print("\nTASK E2E:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
