"""The guards that stop a backend from outliving the app that started it."""

from __future__ import annotations

import os
import subprocess
import sys
import time

from webscripts.lifetime import Lifetime, parent_is_alive


def test_a_live_process_is_seen_as_alive():
    assert parent_is_alive(os.getpid())


def test_a_dead_process_is_seen_as_dead():
    child = subprocess.Popen([sys.executable, "-c", "pass"])
    child.wait()

    assert not parent_is_alive(child.pid)


def test_pid_zero_means_nobody_is_watching():
    assert parent_is_alive(0)


def test_it_exits_when_the_app_is_gone():
    child = subprocess.Popen([sys.executable, "-c", "pass"])
    child.wait()
    life = Lifetime(shutdown=lambda: None, parent_pid=child.pid)

    assert "gone" in life.should_exit(busy=False)


def test_it_stays_while_the_app_lives():
    life = Lifetime(shutdown=lambda: None, parent_pid=os.getpid())
    life.client_connected()

    assert life.should_exit(busy=False) == ""


def test_it_waits_out_the_grace_period_after_the_ui_disappears():
    life = Lifetime(shutdown=lambda: None, client_grace=30)
    life.client_connected()
    life.client_gone()

    assert life.should_exit(busy=False) == ""
    assert "no UI" in life.should_exit(busy=False, now=time.time() + 31)


def test_a_running_script_is_never_cut_off():
    life = Lifetime(shutdown=lambda: None, client_grace=1)
    life.client_connected()
    life.client_gone()

    assert life.should_exit(busy=True, now=time.time() + 60) == ""


def test_a_backend_that_never_had_a_ui_keeps_waiting():
    """`python run_server.py` in a terminal must not exit by itself."""
    life = Lifetime(shutdown=lambda: None, client_grace=1)

    assert life.should_exit(busy=False, now=time.time() + 600) == ""


def test_reconnecting_clears_the_countdown():
    life = Lifetime(shutdown=lambda: None, client_grace=1)
    life.client_connected()
    life.client_gone()
    life.client_connected()

    assert life.should_exit(busy=False, now=time.time() + 600) == ""


def test_the_watchdog_thread_fires_the_shutdown():
    child = subprocess.Popen([sys.executable, "-c", "pass"])
    child.wait()
    calls: list[int] = []
    life = Lifetime(shutdown=lambda: calls.append(1), parent_pid=child.pid)

    life.start()
    deadline = time.time() + 8
    while not calls and time.time() < deadline:
        time.sleep(0.1)
    life.stop()

    assert calls, "the parent was gone and nothing happened"
