"""Fill a WebScripts data directory with believable demo content.

Used to drive the app for the documentation screenshots:

    WEBSCRIPTS_HOME=/tmp/demo python3 tools/seed_demo.py
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from webscripts import config  # noqa: E402
from webscripts.accounts import AccountStore  # noqa: E402
from webscripts.tasks import FAILED, OK, PENDING, TaskStore  # noqa: E402
from webscripts.models import Script, Step, Target, Variable  # noqa: E402
from webscripts.storage import Storage  # noqa: E402

HOUR = 3600_000
DAY = 24 * HOUR


def css(value: str, kind: str = "aria") -> list[Target]:
    return [Target(type="css", value=value, kind=kind)]


def xpath(value: str) -> list[Target]:
    return [Target(type="xpath", value=value, kind="text")]


def facebook_theme() -> Script:
    return Script(
        name="د فیسبوک ټم بدلول",
        start_url="https://www.facebook.com/settings",
        steps=[
            Step(action="goto", url="https://www.facebook.com/", label="facebook.com"),
            Step(action="click", targets=css('[aria-label="Menu"]'), label="Menu",
                 tag="div", delay_ms=900),
            Step(action="click", targets=css('[data-testid="settings-link"]', "testid"),
                 label="تنظیمات او محرمیت", tag="a", delay_ms=1200),
            Step(action="click",
                 targets=xpath('//span[normalize-space(.)="ښکارېدنه"]'),
                 label="ښکارېدنه", tag="span", delay_ms=800),
            Step(action="select", targets=css('select[name="theme"]', "name"),
                 value="تیاره", option_value="dark", label="theme", tag="select",
                 delay_ms=700),
            Step(action="click", targets=css("button#save", "id"), label="خوندي کول",
                 tag="button", delay_ms=600),
            Step(action="assert_text", value="تنظیمات خوندي شول", delay_ms=500),
        ],
    )


def gmail_unread() -> Script:
    return Script(
        name="جیمیل — نالوستل نښه کول",
        start_url="https://mail.google.com/",
        steps=[
            Step(action="goto", url="https://mail.google.com/", label="mail.google.com"),
            *[
                Step(action="click", targets=css(f'[data-row="{i}"]', "testid"),
                     label=f"پیغام {i}", tag="div", delay_ms=450)
                for i in range(1, 10)
            ],
            Step(action="click", targets=css('[aria-label="Mark as unread"]'),
                 label="Mark as unread", tag="div", delay_ms=700),
            Step(action="press_key", targets=css("body", "path"), value="ESCAPE",
                 label="body", delay_ms=300),
        ],
    )


def linkedin_messages() -> Script:
    return Script(
        name="د لینکډان پیغامونه",
        start_url="https://www.linkedin.com/messaging",
        steps=[
            Step(action="goto", url="https://www.linkedin.com/messaging",
                 label="linkedin.com"),
            Step(action="click", targets=css('[aria-label="پیغامونه"]'),
                 label="پیغامونه", tag="a", delay_ms=800),
            Step(action="click", targets=css(".msg-thread:nth-of-type(1)", "class"),
                 label="لومړی خبرې اترې", tag="li", delay_ms=900),
            Step(action="type", targets=css('div[role="textbox"]', "role"),
                 value="مننه، ژر ځواب درکوم.", label="پیغام ولیکئ", tag="div",
                 delay_ms=1100),
            Step(action="press_key", targets=css('div[role="textbox"]', "role"),
                 value="ENTER", label="پیغام ولیکئ", delay_ms=400),
            Step(action="click", targets=css('[aria-label="Close"]'), label="Close",
                 tag="button", delay_ms=500),
        ],
    )


def youtube_history() -> Script:
    steps = [Step(action="goto", url="https://www.youtube.com/feed/history",
                  label="youtube.com")]
    steps += [
        Step(action="click", targets=css(f'[data-video="{i}"]', "testid"),
             label=f"ویډیو {i} لرې کړه", tag="button", delay_ms=380)
        for i in range(1, 13)
    ]
    steps.append(
        Step(action="click", targets=css('[aria-label="ټول پاک کړه"]'),
             label="ټول پاک کړه", tag="button", delay_ms=700)
    )
    steps.append(
        Step(action="click", targets=css("button.confirm", "class"), label="تایید",
             tag="button", delay_ms=500)
    )
    return Script(
        name="یوټیوب — لیدل شوي پاکول",
        start_url="https://www.youtube.com/feed/history",
        steps=steps,
    )


def x_daily_post() -> Script:
    return Script(
        name="ایکس — ورځنی پوسټ",
        start_url="https://x.com/compose/post",
        steps=[
            Step(action="goto", url="https://x.com/compose/post", label="x.com"),
            Step(action="click", targets=css('[data-testid="tweetTextarea_0"]', "testid"),
                 label="څه روان دي؟", tag="div", delay_ms=800),
            Step(action="type", targets=css('[data-testid="tweetTextarea_0"]', "testid"),
                 value="{{message}}", label="څه روان دي؟", tag="div", delay_ms=1400),
            Step(action="click", targets=css('[data-testid="tweetButton"]', "testid"),
                 label="پوسټ", tag="button", delay_ms=600),
        ],
        variables=[Variable(name="message", label="د پوسټ متن", default="سلام!")],
    )


def instagram_story() -> Script:
    return Script(
        name="انسټاګرام — سټوري کتل",
        start_url="https://www.instagram.com/",
        steps=[
            Step(action="goto", url="https://www.instagram.com/", label="instagram.com"),
            Step(action="click", targets=css('[aria-label="Story"]'), label="سټوري",
                 tag="div", delay_ms=900),
            Step(action="press_key", targets=css("body", "path"), value="ARROW_RIGHT",
                 label="body", delay_ms=1200, enabled=False),
            Step(action="press_key", targets=css("body", "path"), value="ESCAPE",
                 label="body", delay_ms=400),
        ],
    )


def main() -> int:
    config.ensure_dirs()
    now = int(time.time() * 1000)
    storage = Storage()
    accounts = AccountStore()

    plan = [
        (facebook_theme(), now - 2 * 60_000, True),
        (gmail_unread(), now - 5 * HOUR, True),
        (linkedin_messages(), now - DAY, False),
        (youtube_history(), now - 2 * DAY, True),
        (x_daily_post(), now - 3 * DAY, True),
        (instagram_story(), None, None),
    ]
    for script, last_run, ok in plan:
        script.last_run_at = last_run
        script.last_run_ok = ok
        saved = storage.save(script)
        # storage.save() stamps updated_at; keep the demo ordering readable.
        saved.updated_at = last_run or (now - 6 * DAY)
        storage.save(saved)

    accounts.set_limit("facebook", 2)
    accounts.set_limit("x", 3)
    accounts.set_limit("instagram", 1)

    seeds = [
        ("facebook", "کاري حساب", "Elyas Omar | Facebook", 14, now - 2 * 60_000),
        ("facebook", "شخصي حساب", "Facebook", 12, now - 3 * DAY),
        ("x", "رسمي پاڼه", "Home / X", 9, now - 5 * HOUR),
        ("x", "دویم حساب", "X", 8, None),
        ("instagram", "انسټاګرام", "Instagram", 11, now - DAY),
        ("google", "جیمیل", "Inbox — Gmail", 17, now - 5 * HOUR),
        ("linkedin", "لینکډان", "LinkedIn", 7, now - DAY),
    ]
    for category, label, display, cookies, used in seeds:
        account = accounts.create(category, label)
        accounts.save_cookies(
            account.id,
            [
                {
                    "name": f"demo_{index}",
                    "value": "x" * 24,
                    "domain": f".{category}.com",
                    "path": "/",
                }
                for index in range(cookies)
            ],
        )
        accounts.update(account.id, display_name=display, last_used_at=used)

    # ---- tasks: one of each colour, so the list shows what it looks like
    tasks = TaskStore()
    by_label = {a.label: a for a in accounts.accounts()}
    script_by_name = {s.name: s for s in storage.list()}

    def account_ids(*labels: str) -> list[str]:
        return [by_label[label].id for label in labels if label in by_label]

    task_plan = [
        # (name, script name, account labels, concurrency, run states, when)
        (
            "د ایکس ورځنی پوست",
            "ایکس — ورځنی پوسټ",
            ("رسمي پاڼه", "دویم حساب"),
            2,
            (OK, PENDING),          # stopped half way: yellow
            now - 40 * 60_000,
        ),
        (
            "د فیسبوک ټم بدلول",
            "د فیسبوک ټم بدلول",
            ("کاري حساب", "شخصي حساب"),
            2,
            (OK, OK),               # everything done: green
            now - 3 * HOUR,
        ),
        (
            "د لینکډان پیغامونه",
            "د لینکډان پیغامونه",
            ("لینکډان",),
            1,
            (FAILED,),              # failed: red
            now - DAY,
        ),
        (
            "د انسټاګرام سټوري",
            "انسټاګرام — سټوري کتل",
            ("انسټاګرام",),
            1,
            (PENDING,),             # never run: grey
            None,
        ),
    ]
    for name, script_name, labels, lanes, states, when in task_plan:
        script = script_by_name.get(script_name)
        ids = account_ids(*labels)
        task = tasks.create(
            name=name,
            script_id=script.id if script else "",
            account_ids=ids,
            concurrency=lanes,
        )
        for account_id, state in zip(ids, states):
            run = task.run_for(account_id)
            run.status = state
            if state != PENDING:
                run.started_at = when
                run.finished_at = when
                run.total = len(script.steps) if script else 0
                run.completed = run.total if state == OK else max(0, run.total - 2)
                if state == FAILED:
                    run.error = "عنصر ونه موندل شو: «پیغامونه»"
        task.last_run_at = when
        task.settle()
        tasks.save(task)
        task.updated_at = when or (now - 6 * DAY)
        tasks.save(task)

    print(
        f"seeded {len(plan)} scripts, {len(seeds)} accounts and "
        f"{len(task_plan)} tasks in {config.BASE_DIR}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
