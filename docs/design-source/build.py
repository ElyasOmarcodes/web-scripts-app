"""Generate the macOS-style mockup pages (design spec for the Flutter UI)."""

from pathlib import Path

OUT = Path(__file__).parent

I = {
    "search": '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
    "grid": '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
    "file": '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    "record": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.4" fill="currentColor" stroke="none"/>',
    "pulse": '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
    "gear": '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
    "help": '<circle cx="12" cy="12" r="9"/><path d="M9.6 9.5a2.5 2.5 0 0 1 4.9.8c0 1.7-2.5 2.2-2.5 3.7"/><circle cx="12" cy="17.5" r="0.6" fill="currentColor"/>',
    "play": '<path d="M8 5.5v13l11-6.5z" fill="currentColor" stroke="none"/>',
    "stop": '<rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor" stroke="none"/>',
    "plus": '<path d="M12 5v14M5 12h14"/>',
    "more": '<circle cx="6" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="18" cy="12" r="1.4" fill="currentColor" stroke="none"/>',
    "refresh": '<path d="M20 11a8 8 0 1 0-1.2 5.4"/><path d="M20 5v6h-6"/>',
    "back": '<path d="M15 19l-7-7 7-7"/>',
    "fwd": '<path d="M9 5l7 7-7 7"/>',
    "check": '<path d="M4.5 12.5l5 5 10-11"/>',
    "trash": '<path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13h10l1-13"/>',
    "eye": '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
    "pencil": '<path d="M4 20h4L20 8a2.8 2.8 0 0 0-4-4L4 16z"/>',
    "grip": '<circle cx="9" cy="7" r="1.3" fill="currentColor" stroke="none"/><circle cx="15" cy="7" r="1.3" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="9" cy="17" r="1.3" fill="currentColor" stroke="none"/><circle cx="15" cy="17" r="1.3" fill="currentColor" stroke="none"/>',
    "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.8 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.8-3.8-9S9.5 5.6 12 3z"/>',
    "clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.3l3.4 2"/>',
    "bolt": '<path d="M13 2L4.5 13.5H11l-1 8.5 8.5-11.5H12z"/>',
    "shield": '<path d="M12 3l8 3.2v5.4c0 4.7-3.3 8.6-8 9.9-4.7-1.3-8-5.2-8-9.9V6.2z"/>',
    "folder": '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l2 2.5h7.8A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>',
    "keyboard": '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h10"/>',
    "cursor": '<path d="M5 3l14 7.5-6.2 1.7L9.7 19z"/>',
    "download": '<path d="M12 4v11m0 0l-4.2-4.2M12 15l4.2-4.2M4.5 19h15"/>',
}


def icon(name: str, size: int = 16, width: float = 1.6, color: str = "currentColor") -> str:
    return (
        f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" '
        f'stroke="{color}" stroke-width="{width}" stroke-linecap="round" '
        f'stroke-linejoin="round">{I[name]}</svg>'
    )


def titlebar(title: str, subtitle: str = "", tools: str = "") -> str:
    sub = f' <span class="subtitle">{subtitle}</span>' if subtitle else ""
    return f"""
  <div class="titlebar">
    <div class="lights"><i class="light close"></i><i class="light min"></i><i class="light max"></i></div>
    <div class="title">{title}{sub}</div>
    <div class="toolbar">{tools}</div>
  </div>"""


NAV = [
    ("grid", "داشبورډ", "", "dashboard"),
    ("file", "سکریپټونه", "12", "scripts"),
    ("record", "ثبتونکی", "", "recorder"),
    ("pulse", "پېښې", "", "activity"),
]
NAV2 = [
    ("gear", "تنظیمات", "", "settings"),
    ("help", "مرسته", "", "help"),
]


def sidebar(active: str, status: str = "", status_dot: str = "") -> str:
    def items(rows):
        out = []
        for ico, label, badge, key in rows:
            sel = " selected" if key == active else ""
            b = f'<span class="badge">{badge}</span>' if badge else ""
            out.append(
                f'<div class="side-item{sel}"><span class="ico">{icon(ico)}</span>'
                f"<span>{label}</span>{b}</div>"
            )
        return "\n        ".join(out)

    status = status or "براوزر: Microsoft Edge"
    return f"""
    <aside class="sidebar">
      <div class="search">{icon('search', 13)}<span>لټون</span></div>
      <div class="side-label">اصلي</div>
        {items(NAV)}
      <div class="side-label">نور</div>
        {items(NAV2)}
      <div class="side-foot"><span class="dot {status_dot}"></span><span>{status}</span></div>
    </aside>"""


def page(name: str, title: str, subtitle: str, tools: str, active: str, content: str,
         dark: bool = False, status: str = "", status_dot: str = "", overlay: str = "",
         height: int = 790) -> None:
    stage_h = height + 70
    html = f"""<!doctype html>
<html lang="ps" dir="rtl">
<head>
<meta charset="utf-8">
<title>WebScripts — {title}</title>
<link rel="stylesheet" href="mac.css">
</head>
<body class="{'dark' if dark else ''}">
<div class="stage" style="height:{stage_h}px">
  <div class="window" style="position:relative;height:{height}px">
{titlebar(title, subtitle, tools)}
    <div class="body">
{sidebar(active, status, status_dot)}
      <main class="content">{content}</main>
    </div>
{overlay}
  </div>
</div>
</body>
</html>"""
    (OUT / f"{name}.html").write_text(html, "utf-8")


TOOLS_DEFAULT = (
    f'<button class="tool-btn">{icon("refresh", 15)}</button>'
    f'<span class="tool-sep"></span>'
    f'<button class="tool-btn active">{icon("record", 15)} ثبتول</button>'
)


# ------------------------------------------------------------------ dashboard

def script_row(color, letter, name, meta, pill, pill_class):
    return f"""<div class="row">
            <div class="avatar {color}">{letter}</div>
            <div><div class="name">{name}</div><div class="meta">{meta}</div></div>
            <div class="end"><span class="pill {pill_class}">{pill}</span>
              <span style="color:var(--text-3)">{icon('play', 15)}</span></div>
          </div>"""


def build_dashboard():
    bars = [42, 66, 30, 88, 54, 74, 96]
    days = ["ش", "ی", "د", "س", "چ", "پ", "ج"]
    chart = "".join(
        f'<div class="bar{"" if i != 2 else " dim"}" style="height:{h}%"></div>'
        for i, h in enumerate(bars)
    )
    xs = "".join(f"<span>{d}</span>" for d in days)

    content = f"""
        <div class="scroll">
          <div class="page-head">
            <div>
              <div class="page-title">ښه راغلاست</div>
              <div class="page-sub">ستاسو د اتومات کارونو لنډه کتنه</div>
            </div>
            <div style="margin-inline-start:auto;display:flex;gap:9px">
              <button class="btn">{icon('plus', 15)} نوی سکریپټ</button>
              <button class="btn primary">{icon('record', 15)} نوې لارښوونه</button>
            </div>
          </div>

          <div class="stat-grid">
            <div class="stat blue"><div class="k">{icon('file', 14)} ټول سکریپټونه</div>
              <div><div class="v">12</div><div class="t">۳ نوي دا اونۍ</div></div></div>
            <div class="stat green"><div class="k">{icon('check', 14)} بریالي چلونه</div>
              <div><div class="v">46</div><div class="t">له ۴۸ څخه</div></div></div>
            <div class="stat orange"><div class="k">{icon('clock', 14)} وخت خوندي شوی</div>
              <div><div class="v">3.2</div><div class="t">ساعته دا میاشت</div></div></div>
            <div class="stat purple"><div class="k">{icon('bolt', 14)} بریالیتوب</div>
              <div><div class="v">96%</div><div class="t">وروستي ۳۰ چلونه</div></div></div>
          </div>

          <div class="panels">
            <div class="panel">
              <div class="panel-head">وروستي سکریپټونه <span class="more">ټول وګوره</span></div>
              <div class="panel-body">
                {script_row('bg-blue', 'ف', 'د فیسبوک ټم بدلول', '۸ ګامه · ۲ دقیقې مخکې', 'بریالی', 'ok')}
                {script_row('bg-purple', 'ج', 'جیمیل — نالوستل نښه کول', '۱۲ ګامه · نن ۰۹:۱۴', 'بریالی', 'ok')}
                {script_row('bg-orange', 'ل', 'د لینکډان پیغامونه', '۶ ګامه · پرون', 'ناکام', 'bad')}
                {script_row('bg-teal', 'ی', 'یوټیوب — لیدل شوي پاکول', '۱۵ ګامه · ۲ ورځې مخکې', 'بریالی', 'ok')}
                {script_row('bg-pink', 'ټ', 'ټویټر — ورځنی پوسټ', '۹ ګامه · ۳ ورځې مخکې', 'بریالی', 'ok')}
              </div>
            </div>

            <div class="panel">
              <div class="panel-head">د اونۍ چلونه</div>
              <div class="chart">{chart}</div>
              <div class="chart-x">{xs}</div>
              <div style="padding:0 6px 6px">
                <div class="row"><div class="avatar bg-green">{icon('check', 15)}</div>
                  <div><div class="name">وروستی چلون بریالی و</div>
                  <div class="meta">«د فیسبوک ټم» · ۸/۸ ګامه · ۱۲.۴s</div></div></div>
              </div>
            </div>
          </div>

          <div class="quick-grid">
            <div class="quick"><div class="ic bg-blue">{icon('record', 17)}</div>
              <div><div class="t1">نوې لارښوونه ثبت کړه</div>
                   <div class="t2">براوزر پرانیزه او خپله لار وښایه</div></div></div>
            <div class="quick"><div class="ic bg-green">{icon('play', 17)}</div>
              <div><div class="t1">وروستی سکریپټ بیا وچلوه</div>
                   <div class="t2">«د فیسبوک ټم» · ۸ ګامه</div></div></div>
            <div class="quick"><div class="ic bg-orange">{icon('gear', 17)}</div>
              <div><div class="t1">براوزر بدل کړه</div>
                   <div class="t2">اوس: Microsoft Edge 141</div></div></div>
          </div>
        </div>"""
    page("01-dashboard", "داشبورډ", "", TOOLS_DEFAULT, "dashboard", content, height=780)


# -------------------------------------------------------------------- scripts

def script_card(color, letter, name, url, steps, when, pill, pill_class):
    return f"""<div class="panel" style="padding:14px">
              <div style="display:flex;align-items:center;gap:11px;margin-bottom:12px">
                <div class="avatar {color}" style="width:36px;height:36px;border-radius:10px;font-size:15px">{letter}</div>
                <div style="min-width:0">
                  <div class="name" style="font-size:13.5px">{name}</div>
                  <div class="meta" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:210px">{url}</div>
                </div>
                <div class="end" style="margin-inline-start:auto;color:var(--text-3)">{icon('more', 16)}</div>
              </div>
              <div style="display:flex;align-items:center;gap:8px">
                <span class="pill {pill_class}">{pill}</span>
                <span class="pill">{steps} ګامه</span>
                <span style="font-size:11.5px;color:var(--text-3);margin-inline-start:auto">{when}</span>
              </div>
              <div style="display:flex;gap:7px;margin-top:13px">
                <button class="btn primary">{icon('play', 13)} چلول</button>
                <button class="btn">{icon('pencil', 14)}</button>
                <button class="btn">{icon('trash', 14)}</button>
                <span style="margin-inline-start:auto;align-self:center;font-size:11.5px;color:var(--text-3)">۹۶٪ بریالیتوب</span>
              </div>
            </div>"""


def build_scripts():
    cards = "\n            ".join([
        script_card('bg-blue', 'ف', 'د فیسبوک ټم بدلول', 'facebook.com/settings', 8, '۲ دقیقې مخکې', 'بریالی', 'ok'),
        script_card('bg-purple', 'ج', 'جیمیل — نالوستل نښه کول', 'mail.google.com', 12, 'نن ۰۹:۱۴', 'بریالی', 'ok'),
        script_card('bg-orange', 'ل', 'د لینکډان پیغامونه', 'linkedin.com/messaging', 6, 'پرون', 'ناکام', 'bad'),
        script_card('bg-teal', 'ی', 'یوټیوب — لیدل شوي پاکول', 'youtube.com/feed/history', 15, '۲ ورځې مخکې', 'بریالی', 'ok'),
        script_card('bg-pink', 'ټ', 'ټویټر — ورځنی پوسټ', 'x.com/compose', 9, '۳ ورځې مخکې', 'بریالی', 'ok'),
        script_card('bg-gray', 'ن', 'نوی سکریپټ (مسوده)', '—', 0, 'لا نه دی چلول شوی', 'مسوده', ''),
    ])
    content = f"""
        <div class="scroll">
          <div class="page-head">
            <div><div class="page-title">سکریپټونه</div>
                 <div class="page-sub">۶ سکریپټه · ۵۰ ګامه په ټوله کې</div></div>
            <div style="margin-inline-start:auto;display:flex;gap:9px;align-items:center">
              <div class="segmented"><span class="on">ټول</span><span>بریالي</span><span>ناکام</span></div>
              <button class="btn">{icon('plus', 15)} نوی سکریپټ</button>
            </div>
          </div>
          <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:14px">
            {cards}
          </div>
        </div>"""
    page("02-scripts", "سکریپټونه", "", TOOLS_DEFAULT, "scripts", content, height=640)


# --------------------------------------------------------------- script detail

def step(n, txt, loc, cls=""):
    return f"""<div class="step {cls}">
              <span style="color:var(--text-3)">{icon('grip', 15)}</span>
              <span class="n">{n}</span>
              <div><div class="txt">{txt}</div><div class="loc">{loc}</div></div>
              <span class="act">{icon('pencil', 14)}{icon('eye', 14)}{icon('trash', 14)}</span>
            </div>"""


def build_detail():
    steps = "\n            ".join([
        step(1, 'پرانیستل: facebook.com', 'https://www.facebook.com/', 'done'),
        step(2, 'کلیک: Menu', '[aria-label="Menu"]', 'done'),
        step(3, 'کلیک: تنظیمات او محرمیت', '[data-testid="settings-link"]', 'done'),
        step(4, 'کلیک: ښکارېدنه', '//span[normalize-space(.)="ښکارېدنه"]', 'active'),
        step(5, 'غوره کول «تیاره» له: theme', 'select[name="theme"]'),
        step(6, 'کلیک: خوندي کول', 'button#save'),
        step(7, 'د متن کتنه: تنظیمات خوندي شول', 'document.body'),
    ])
    content = f"""
        <div style="padding:16px 26px 0;display:flex;align-items:center;gap:12px">
          <button class="btn ghost">{icon('back', 16)}</button>
          <div><div style="font-size:18px;font-weight:650">د فیسبوک ټم بدلول</div>
               <div class="page-sub">۷ ګامه · facebook.com · وروستی چلون: بریالی</div></div>
          <div style="margin-inline-start:auto;display:flex;gap:9px;align-items:center">
            <button class="btn">{icon('stop', 14)} ودروه</button>
            <button class="btn primary">{icon('play', 14)} چلول</button>
          </div>
        </div>

        <div style="padding:14px 26px 0">
          <div class="panel" style="padding:12px 14px;display:flex;align-items:center;gap:20px">
            <div style="display:flex;align-items:center;gap:10px;min-width:210px">
              <span style="font-size:12.5px;color:var(--text-2)">چټکتیا</span>
              <div class="slider" style="width:120px"><div class="fill" style="width:38%"></div>
                <div class="knob" style="inset-inline-start:38%"></div></div>
              <span style="font-size:12.5px;font-weight:600">1.5×</span>
            </div>
            <div style="display:flex;align-items:center;gap:9px"><span class="switch"><i></i></span>
              <span style="font-size:12.5px">پټ چلول</span></div>
            <div style="display:flex;align-items:center;gap:9px"><span class="switch on"><i></i></span>
              <span style="font-size:12.5px">براوزر پرانیستی پرېږده</span></div>
            <div style="margin-inline-start:auto;display:flex;align-items:center;gap:8px">
              <span class="pill blue">۴ / ۷ ګامه</span>
              <div class="slider" style="width:130px"><div class="fill" style="width:57%"></div></div>
            </div>
          </div>
        </div>

        <div class="scroll" style="padding-top:14px">
          <div class="panel">
            <div class="panel-head">ګامونه <span class="more">+ ګام زیات کړه</span></div>
            <div class="panel-body">
            {steps}
            </div>
          </div>
          <div style="height:14px"></div>
          <div class="console">
            <div class="ln">{icon('play', 12)} <span>۳/۷ کلیک: تنظیمات او محرمیت</span></div>
            <div class="ln ok">{icon('check', 12)} <span>ګام ۳ بشپړ شو (۰.۸s)</span></div>
            <div class="ln">{icon('play', 12)} <span>۴/۷ کلیک: ښکارېدنه</span></div>
          </div>
        </div>"""
    page("03-script-detail", "د فیسبوک ټم بدلول", "", TOOLS_DEFAULT, "scripts", content, height=720)


# ------------------------------------------------------------------- recorder

def build_recorder_sheet():
    base_content = """<div class="scroll"><div class="page-head">
            <div><div class="page-title">ثبتونکی</div>
            <div class="page-sub">خپله لار یو ځل وښایاست، پروګرام به یې زده کړي</div></div></div></div>"""
    overlay = f"""
    <div class="sheet-backdrop">
      <div class="sheet">
        <div class="sheet-body">
          <div style="display:flex;align-items:center;gap:11px;margin-bottom:14px">
            <div class="avatar bg-pink" style="width:34px;height:34px;border-radius:10px">{icon('record', 17)}</div>
            <div><h3>نوې لارښوونه ثبتول</h3>
                 <p class="sub" style="margin:0">براوزر پرانیستل کېږي — خپل کار پکې وکړئ</p></div>
          </div>
          <div class="form-row"><label>د سکریپټ نوم</label>
            <div class="field">د فیسبوک ټم بدلول</div></div>
          <div class="form-row"><label>پیل پته</label>
            <div class="field">https://www.facebook.com</div></div>
          <div class="form-row"><label>براوزر</label>
            <div style="display:flex;gap:8px">
              <div class="field" style="flex:1;gap:8px"><span class="dot"></span>Microsoft Edge 141.0.2 <span style="margin-inline-start:auto;color:var(--text-3)">{icon('fwd', 13)}</span></div>
            </div></div>
          <div class="g-row" style="padding:6px 0">
            <div><div class="label">سکرول هم ثبت کړه</div>
                 <div class="hint">ډېری وخت اړتیا نشته</div></div>
            <div class="end"><span class="switch"><i></i></span></div>
          </div>
        </div>
        <div class="sheet-foot">
          <button class="btn record lg">{icon('record', 15)} ثبتول پیل کړه</button>
          <button class="btn lg">لغوه</button>
        </div>
      </div>
    </div>"""
    page("04-recorder-new", "ثبتونکی", "", TOOLS_DEFAULT, "recorder", base_content, overlay=overlay, height=660)


def build_recording_live():
    live = "\n            ".join([
        step(1, 'پرانیستل: facebook.com', 'https://www.facebook.com/', 'done'),
        step(2, 'کلیک: Menu', '[aria-label="Menu"]', 'done'),
        step(3, 'کلیک: تنظیمات او محرمیت', '[data-testid="settings-link"]', 'done'),
        step(4, 'کلیک: ښکارېدنه', '//span[normalize-space(.)="ښکارېدنه"]', 'done'),
    ])
    content = f"""
        <div class="scroll">
          <div class="page-head">
            <div style="display:flex;align-items:center;gap:12px">
              <span class="rec-dot"></span>
              <div><div class="page-title">ثبتول روان دي…</div>
                   <div class="page-sub">په براوزر کې خپل کار وکړئ — هر کلیک ثبتېږي</div></div>
            </div>
            <div style="margin-inline-start:auto;display:flex;gap:9px;align-items:center">
              <span class="pill live">۰۰:۴۲</span>
              <button class="btn danger">{icon('stop', 15)} ثبتول ودروه</button>
            </div>
          </div>

          <div class="stat-grid" style="grid-template-columns:repeat(3,1fr)">
            <div class="stat blue"><div class="k">{icon('cursor', 14)} ثبت شوي ګامونه</div>
              <div><div class="v">4</div><div class="t">وروستی: کلیک ښکارېدنه</div></div></div>
            <div class="stat purple"><div class="k">{icon('globe', 14)} اوسنۍ پاڼه</div>
              <div><div class="v" style="font-size:16px;line-height:1.5">facebook.com<br>/settings</div><div class="t">۲ پاڼې لیدل شوې</div></div></div>
            <div class="stat green"><div class="k">{icon('keyboard', 14)} براوزر</div>
              <div><div class="v" style="font-size:19px">Edge</div><div class="t">141.0.2 · پروفایل فعال</div></div></div>
          </div>

          <div class="panel">
            <div class="panel-head"><span class="rec-dot"></span> ژوندي ګامونه</div>
            <div class="panel-body">
            {live}
            <div class="step" style="opacity:.55"><span class="n">…</span>
              <div><div class="txt">د راتلونکي کار انتظار…</div></div></div>
            </div>
          </div>
        </div>"""
    page("05-recording-live", "ثبتونکی", "— ثبتول روان دي", TOOLS_DEFAULT, "recorder",
         content, status="ثبتول روان دي", status_dot="red", height=700)


# ------------------------------------------------------------------- settings

def browser_row(name, version, path, installed, selected):
    dot = "" if installed else "gray"
    state = (f'<span class="pill ok">نصب دی</span>' if installed
             else '<span class="pill">نه دی موندل شوی</span>')
    ver = f'<div class="hint">{version} · {path}</div>' if installed else \
          '<div class="hint">پدې کمپیوټر کې ونه موندل شو</div>'
    return f"""<div class="g-row">
            <span class="radio {'on' if selected else ''}"></span>
            <span class="dot {dot}"></span>
            <div><div class="label">{name}</div>{ver}</div>
            <div class="end">{state}</div>
          </div>"""


def build_settings():
    # Backslashes cannot live inside f-string expressions, so build these first.
    edge_row = browser_row(
        "Microsoft Edge", "141.0.2623.75",
        "C:\\Program Files (x86)\\Microsoft\\Edge\\…", True, False)
    chrome_row = browser_row(
        "Google Chrome", "141.0.7390.54",
        "C:\\Program Files\\Google\\Chrome\\…", True, False)
    brave_row = browser_row("Brave", "", "", False, False)
    firefox_row = browser_row("Mozilla Firefox", "", "", False, False)
    content = f"""
        <div class="scroll">
          <div class="page-head">
            <div><div class="page-title">تنظیمات</div>
                 <div class="page-sub">براوزر، ښکارېدنه او د چلولو چلند</div></div>
            <div style="margin-inline-start:auto"><button class="btn">{icon('refresh', 15)} بیا لټون</button></div>
          </div>

          <div class="group-title">براوزر</div>
          <div class="group">
            <div class="g-row">
              <span class="radio on"></span>
              <div><div class="label">اتوماتیک غوره کول</div>
                   <div class="hint">لومړی Edge، بیا Chrome، بیا هر موجود Chromium</div></div>
              <div class="end"><span class="pill blue">اوس: Edge</span></div>
            </div>
            {edge_row}
            {chrome_row}
            {brave_row}
            {firefox_row}
          </div>

          <div class="group-title">ښکارېدنه</div>
          <div class="group">
            <div class="g-row"><div><div class="label">ښکارېدنه</div>
              <div class="hint">د سیسټم سره سم بدلېږي</div></div>
              <div class="end"><div class="segmented"><span class="on">سیسټم</span><span>رڼا</span><span>تیاره</span></div></div></div>
            <div class="g-row"><div class="label">د تاکید رنګ</div>
              <div class="end" style="gap:9px">
                <span class="swatch sel" style="background:#007aff"></span>
                <span class="swatch" style="background:#af52de"></span>
                <span class="swatch" style="background:#ff2d55"></span>
                <span class="swatch" style="background:#ff9500"></span>
                <span class="swatch" style="background:#34c759"></span>
              </div></div>
          </div>

          <div class="group-title">چلول</div>
          <div class="group">
            <div class="g-row"><div><div class="label">د چلولو چټکتیا</div>
              <div class="hint">لوړه چټکتیا = لنډ ځنډونه</div></div>
              <div class="end" style="gap:12px">
                <div class="slider" style="width:150px"><div class="fill" style="width:30%"></div>
                  <div class="knob" style="inset-inline-start:30%"></div></div>
                <span style="font-size:12.5px;font-weight:600;width:34px">1.0×</span></div></div>
            <div class="g-row"><div><div class="label">پټ چلول (headless)</div>
              <div class="hint">براوزر نه ښکاري — ګړندی دی</div></div>
              <div class="end"><span class="switch"><i></i></span></div></div>
            <div class="g-row"><div><div class="label">ننوتنې وساته</div>
              <div class="hint">ځانګړی پروفایل — یو ځل ننوځئ، تل ننوتلي یاست</div></div>
              <div class="end"><span class="switch on"><i></i></span></div></div>
            <div class="g-row"><div><div class="label">د ګام انتظار</div>
              <div class="hint">تر څو یو عنصر ونه موندل شي</div></div>
              <div class="end"><div class="field" style="width:78px">15 ثانیې</div></div></div>
          </div>

          <div class="group-title">ذخیره</div>
          <div class="group">
            <div class="g-row"><span style="color:var(--text-2)">{icon('folder', 17)}</span>
              <div><div class="label">د سکریپټونو فولډر</div>
                   <div class="hint">%LOCALAPPDATA%\\WebScripts\\scripts</div></div>
              <div class="end"><button class="btn">پرانیزه</button></div></div>
            <div class="g-row"><span style="color:var(--text-2)">{icon('shield', 17)}</span>
              <div><div class="label">د براوزر پروفایل</div>
                   <div class="hint">۱۲۴ MB · د Edge ننوتنې پکې خوندي دي</div></div>
              <div class="end"><button class="btn">پاکول</button></div></div>
          </div>
        </div>"""
    page("06-settings", "تنظیمات", "", TOOLS_DEFAULT, "settings", content, height=980)


# ------------------------------------------------------------------- activity

def build_activity():
    lines = [
        ("ok", "check", "«د فیسبوک ټم» بریالی و — ۸/۸ ګامه (۱۲.۴s)", "۱۴:۰۲"),
        ("", "play", "ګام ۸/۸ کلیک: خوندي کول", "۱۴:۰۲"),
        ("", "play", "ګام ۷/۸ غوره کول «تیاره»", "۱۴:۰۱"),
        ("", "play", "ګام ۶/۸ کلیک: ښکارېدنه", "۱۴:۰۱"),
        ("err", "trash", "«لینکډان» ناکام — عنصر ونه موندل شو: «پیغامونه»", "۱۳:۴۸"),
        ("", "record", "ثبتول ودرېدل — ۶ ګامه خوندي شول", "۱۳:۳۰"),
        ("", "globe", "براوزر پیل شو: Microsoft Edge 141", "۱۳:۲۸"),
    ]
    rows = "\n              ".join(
        f'<div class="ln {c}">{icon(i, 13)}<span>{t}</span>'
        f'<span style="margin-inline-start:auto;color:var(--text-3)">{when}</span></div>'
        for c, i, t, when in lines
    )
    content = f"""
        <div class="scroll">
          <div class="page-head">
            <div><div class="page-title">پېښې</div>
                 <div class="page-sub">د ثبتولو او چلولو ژوندی جریان</div></div>
            <div style="margin-inline-start:auto;display:flex;gap:9px;align-items:center">
              <div class="segmented"><span class="on">ټول</span><span>ګامونه</span><span>تېروتنې</span></div>
              <button class="btn">پاکول</button>
            </div>
          </div>
          <div class="panel"><div class="panel-body" style="padding:10px 12px">
            <div class="console" style="background:transparent;padding:0">
              {rows}
            </div>
          </div></div>
        </div>"""
    page("07-activity", "پېښې", "", TOOLS_DEFAULT, "activity", content, dark=True, height=640)


def build_empty():
    content = f"""
        <div class="scroll">
          <div class="empty">
            <div class="big">{icon('record', 30, 1.5)}</div>
            <h3>لا هېڅ سکریپټ نشته</h3>
            <p style="max-width:430px;margin:0 auto 20px;line-height:1.7">
              «نوې لارښوونه» ووهئ — براوزر پرانیستل کېږي، خپله لار یو ځل تعقیب کړئ
              (مینو ← تنظیمات ← ټم)، بیا ودرېږئ. له دې وروسته پروګرام هماغه لار
              پخپله ټکی په ټکی بیا ترسره کوي.
            </p>
            <button class="btn primary lg">{icon('record', 15)} نوې لارښوونه ثبت کړه</button>
          </div>
        </div>"""
    page("08-empty", "سکریپټونه", "", TOOLS_DEFAULT, "scripts", content, height=620)


if __name__ == "__main__":
    build_dashboard()
    build_scripts()
    build_detail()
    build_recorder_sheet()
    build_recording_live()
    build_settings()
    build_activity()
    build_empty()
    print("built:", sorted(p.name for p in OUT.glob("*.html")))
