"""Tasks: one script, many accounts, and remembering where it stopped."""

from __future__ import annotations

import pytest

from webscripts.tasks import (
    DONE,
    DRAFT,
    FAILED,
    OK,
    PARTIAL,
    PENDING,
    STOPPED,
    Task,
    TaskStore,
)


@pytest.fixture()
def store(tmp_path):
    return TaskStore(tmp_path / "tasks.json")


def task_with(*account_ids: str, **fields) -> Task:
    task = Task(name="ټیسټ", script_id="scr_1", account_ids=list(account_ids), **fields)
    task.sync_runs()
    return task


# ------------------------------------------------------------------ storage


def test_a_new_task_gets_one_run_row_per_account(store):
    task = store.create(name="ایکس پوستونه", script_id="scr_1",
                        account_ids=["a1", "a2", "a3"])

    assert [r.account_id for r in task.runs] == ["a1", "a2", "a3"]
    assert {r.status for r in task.runs} == {PENDING}
    assert task.status == DRAFT


def test_tasks_survive_a_reload(store, tmp_path):
    store.create(name="کار", script_id="scr_1", account_ids=["a1"])

    again = TaskStore(tmp_path / "tasks.json")

    assert [t.name for t in again.list()] == ["کار"]


def test_changing_the_accounts_keeps_the_results_of_the_ones_that_stay(store):
    task = store.create(script_id="scr_1", account_ids=["a1", "a2"])
    task.run_for("a1").status = OK
    store.save(task)

    updated = store.update(task.id, account_ids=["a2", "a1", "a3"])

    assert [r.account_id for r in updated.runs] == ["a2", "a1", "a3"]
    assert updated.run_for("a1").status == OK
    assert updated.run_for("a3").status == PENDING


def test_a_corrupt_file_starts_empty(tmp_path):
    path = tmp_path / "tasks.json"
    path.write_text("{ not json", encoding="utf-8")

    assert TaskStore(path).list() == []


def test_deleting_an_account_removes_it_from_every_task(store):
    task = store.create(script_id="scr_1", account_ids=["a1", "a2"])

    store.forget_account("a1")

    assert store.get(task.id).account_ids == ["a2"]


def test_deleting_a_script_leaves_the_task_without_one(store):
    task = store.create(script_id="scr_1", account_ids=["a1"])

    store.forget_script("scr_1")

    assert store.get(task.id).script_id == ""


# ------------------------------------------------------------------ colours


def test_all_accounts_done_is_green():
    task = task_with("a1", "a2")
    for run in task.runs:
        run.status = OK

    assert task.settle() == DONE


def test_every_account_failed_is_red():
    task = task_with("a1", "a2")
    for run in task.runs:
        run.status = FAILED

    assert task.settle() == FAILED


def test_some_done_some_failed_is_yellow():
    task = task_with("a1", "a2")
    task.run_for("a1").status = OK
    task.run_for("a2").status = FAILED

    assert task.settle() == PARTIAL


def test_stopped_half_way_is_yellow():
    """Two of three X accounts done, the third never started."""
    task = task_with("a1", "a2", "a3")
    task.run_for("a1").status = OK
    task.run_for("a2").status = OK

    assert task.settle() == PARTIAL


# ------------------------------------------------------------------- resume


def test_resume_runs_only_what_is_left():
    task = task_with("a1", "a2", "a3")
    task.run_for("a1").status = OK
    task.run_for("a2").status = FAILED
    task.run_for("a3").status = STOPPED

    assert task.pending_accounts() == ["a2", "a3"]


def test_a_finished_task_has_nothing_to_resume():
    task = task_with("a1")
    task.run_for("a1").status = OK
    task.settle()

    assert task.pending_accounts() == []
    assert not task.can_resume()


def test_a_half_finished_task_can_be_resumed():
    task = task_with("a1", "a2")
    task.run_for("a1").status = OK
    task.settle()

    assert task.can_resume()


def test_a_rerun_clears_only_the_accounts_it_will_run():
    task = task_with("a1", "a2")
    task.run_for("a1").status = OK
    task.run_for("a2").status = FAILED

    task.reset_runs(["a2"])

    assert task.run_for("a1").status == OK
    assert task.run_for("a2").status == PENDING


def test_the_summary_counts_what_the_list_shows():
    task = task_with("a1", "a2", "a3")
    task.run_for("a1").status = OK
    task.run_for("a2").status = FAILED

    summary = task.summary()

    assert (summary["done_count"], summary["failed_count"],
            summary["pending_count"]) == (1, 1, 2)


def test_concurrency_is_the_users_choice():
    """The machine sets the limit, not the app — see machine.py."""
    assert Task(concurrency=9).concurrency == 9
    with pytest.raises(Exception):
        Task(concurrency=0)


def test_a_task_keeps_its_own_log(store):
    task = store.create(name="کار")

    store.append_log(task.id, {"ts": 1, "level": "info", "message": "پیل"})
    store.append_log(task.id, {"ts": 2, "level": "error", "message": "ناکام"})

    assert [e["message"] for e in store.read_log(task.id)] == ["پیل", "ناکام"]


def test_a_task_without_a_log_reads_empty(store):
    assert store.read_log("tsk_nothing") == []


def test_deleting_a_task_takes_its_log_with_it(store):
    task = store.create(name="کار")
    store.append_log(task.id, {"message": "څه"})

    store.delete(task.id)

    assert store.read_log(task.id) == []


def test_the_overview_counts_every_state(store):
    store.create(name="یو")
    running = store.create(name="دوه")
    running.status = "running"
    store.save(running)

    overview = store.overview()

    assert overview["total"] == 2
    assert overview["running"] == 1
    assert overview["draft"] == 1
