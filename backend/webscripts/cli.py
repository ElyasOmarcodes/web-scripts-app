"""Command line interface — usable without the Flutter UI.

    python -m webscripts.cli serve
    python -m webscripts.cli record --name "فیسبوک تم" --url https://facebook.com
    python -m webscripts.cli list
    python -m webscripts.cli play scr_1234abcd
"""

from __future__ import annotations

import argparse
import getpass
import sys
import threading
import time

from . import config
from .session import PLAYING, RECORDING, SessionManager
from .storage import Storage


def _print_event(event: dict) -> None:
    kind = event.get("type")
    message = event.get("message")
    if kind == "log":
        print(f"[{event.get('level', 'info')}] {message}")
    elif kind == "step_recorded":
        print(f"  {event.get('index'):>3}. {message}")
    elif kind == "step_start":
        print(f"  → {event.get('index', 0) + 1}/{event.get('total', '?')} {message}")
    elif kind == "step_error":
        print(f"  ✗ {message}")
    elif kind in {"run_finished", "recording_saved"}:
        print(f"[{kind}] {event.get('status', '')} {event.get('script', '')}")


def cmd_serve(args: argparse.Namespace) -> int:
    from .server import main as serve_main

    print(f"WebScripts API: http://{config.HOST}:{config.PORT}")
    serve_main()
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    scripts = Storage().list()
    if not scripts:
        print("هېڅ سکریپټ نشته.")
        return 0
    for script in scripts:
        state = "" if script.last_run_ok is None else ("ok" if script.last_run_ok else "fail")
        print(f"{script.id}  {len(script.steps):>3} ګامه  {state:<4}  {script.name}")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    script = Storage().get(args.script_id)
    if script is None:
        print("سکریپټ ونه موندل شو", file=sys.stderr)
        return 1
    print(f"{script.name} — {script.start_url}")
    for index, step in enumerate(script.steps, 1):
        flag = " " if step.enabled else "x"
        print(f"{flag} {index:>3}. {step.describe()}")
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    manager = SessionManager()
    manager.bus.subscribe(_print_event)
    manager.start_recording(name=args.name, url=args.url, capture_scroll=args.scroll)

    print("\nثبتول روان دي. کله چې مو کار پای ته ورسېد، دلته Enter کېکاږئ…\n")
    stop = threading.Event()

    def wait_for_enter() -> None:
        try:
            input()
        except EOFError:
            pass
        stop.set()

    threading.Thread(target=wait_for_enter, daemon=True).start()
    while not stop.is_set() and manager.state == RECORDING:
        time.sleep(0.3)
    if manager.state == RECORDING:
        manager.stop_recording()
    else:
        # The browser was closed by hand; the worker already saved.
        time.sleep(0.5)
    return 0


def cmd_play(args: argparse.Namespace) -> int:
    storage = Storage()
    script = storage.get(args.script_id)
    if script is None:
        print("سکریپټ ونه موندل شو", file=sys.stderr)
        return 1

    variables: dict[str, str] = {}
    for variable in script.variables:
        if variable.secret:
            variables[variable.name] = getpass.getpass(f"{variable.label or variable.name}: ")
        elif variable.default:
            variables[variable.name] = variable.default

    manager = SessionManager(storage)
    manager.bus.subscribe(_print_event)
    manager.start_run(
        script.id,
        variables=variables,
        speed=args.speed,
        headless=args.headless,
        keep_open=args.keep_open,
    )
    while manager.state == PLAYING:
        time.sleep(0.3)
    result = manager.status().get("last_result") or {}
    return 0 if result.get("status") == "ok" else 2


def cmd_delete(args: argparse.Namespace) -> int:
    if Storage().delete(args.script_id):
        print("ړنګ شو.")
        return 0
    print("سکریپټ ونه موندل شو", file=sys.stderr)
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="webscripts", description="Record & replay web tasks")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("serve", help="د API سرور چلول").set_defaults(func=cmd_serve)
    sub.add_parser("list", help="د سکریپټونو لیست").set_defaults(func=cmd_list)

    show = sub.add_parser("show", help="د یوه سکریپټ ګامونه")
    show.add_argument("script_id")
    show.set_defaults(func=cmd_show)

    record = sub.add_parser("record", help="نوی سکریپټ ثبتول")
    record.add_argument("--name", default="نوی سکریپټ")
    record.add_argument("--url", default="")
    record.add_argument("--scroll", action="store_true", help="سکرول هم ثبت کړه")
    record.set_defaults(func=cmd_record)

    play = sub.add_parser("play", help="یو سکریپټ چلول")
    play.add_argument("script_id")
    play.add_argument("--speed", type=float, default=1.0)
    play.add_argument("--headless", action="store_true")
    play.add_argument("--keep-open", action="store_true")
    play.set_defaults(func=cmd_play)

    remove = sub.add_parser("delete", help="سکریپټ ړنګول")
    remove.add_argument("script_id")
    remove.set_defaults(func=cmd_delete)

    return parser


def main(argv: list[str] | None = None) -> int:
    config.ensure_dirs()
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
