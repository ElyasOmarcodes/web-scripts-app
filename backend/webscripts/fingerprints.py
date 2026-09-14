"""One browser identity per account — and the whole identity, not just a name.

The user's idea was right: if five accounts all say they are the same browser,
the site sees one person with five accounts. But a user agent on its own is
the *smallest* part of what a site reads, and changing only that makes things
**worse**, not better. A real Chrome sends, all at once:

* the user agent string,
* the ``Sec-CH-UA`` client-hint headers (browser brand, version, platform),
* ``navigator.platform``, ``userAgentData``, ``languages``, ``deviceMemory``,
  ``hardwareConcurrency``, ``maxTouchPoints``,
* the screen size and pixel ratio,
* the graphics card name out of WebGL,
* the timezone.

Set the user agent to "iPhone" and leave the other twelve saying "Windows
desktop, no touch, NVIDIA graphics" and the page has not learned that we are
an iPhone — it has learned that we are lying. That is a far stronger signal
than two accounts sharing one ordinary user agent.

So an identity here is a whole **device**: a hundred of them, each one
internally consistent, each one pinned to an account the moment it is created
and never changed again. Alongside it the account keeps a small random
``seed``; the readings that a real machine would make slightly unique — canvas
pixels, audio, WebGL noise — are nudged by that seed, so two accounts that
happen to carry the same device are still not the same computer, while each
account stays exactly the same computer forever.

The catalogue below is the user's own list of a hundred user agents, with the
rest of the device filled in around each one and a *risk tier* attached:

``SAFE``  Windows desktop Chrome/Edge — what this machine actually is.
``FAIR``  macOS / Linux / ChromeOS desktop — believable, a few details spoofed.
``BOLD``  phones and tablets — a desktop pretending to be a phone. Offered,
          because the list asked for them, but never handed out automatically.
"""

from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass, field
from typing import Iterable, Sequence

SAFE = "safe"
FAIR = "fair"
BOLD = "bold"

TIER_LABEL = {
    SAFE: "ډېر خوندي",
    FAIR: "منځنی",
    BOLD: "پاملرنه غواړي",
}

TIER_NOTE = {
    SAFE: "ویندوز ډیسکټاپ — هماغه څه چې ستاسو کمپیوټر په حقیقت کې دی.",
    FAIR: "مک/لینکس ډیسکټاپ — د باور وړ، خو یو څو جزئیات یې جوړ شوي دي.",
    BOLD: "ګرځنده تلیفون — ډیسکټاپ براوزر ځان تلیفون ښیي، لږ خطر لري.",
}


@dataclass(frozen=True)
class Fingerprint:
    """One complete device, consistent from the user agent down to the GPU."""

    id: str
    label: str
    tier: str
    ua: str
    # What the browser calls itself in client hints.
    brand: str  # Chrome | Microsoft Edge | Safari
    version: int
    ch_platform: str  # Windows | macOS | Linux | Android | Chrome OS | ""
    ch_platform_version: str
    platform: str  # navigator.platform
    mobile: bool
    model: str = ""
    # The screen, as the page reads it.
    screen: tuple[int, int] = (1920, 1080)
    dpr: float = 1.0
    cores: int = 8
    memory: int | None = 8  # navigator.deviceMemory; None on Safari
    touch: int = 0
    webgl_vendor: str = ""
    webgl_renderer: str = ""
    vendor: str = "Google Inc."  # navigator.vendor
    # Safari has no navigator.userAgentData at all; pretending otherwise is a
    # give-away on its own.
    has_ua_data: bool = True
    languages: tuple[str, ...] = ("en-US", "en")

    @property
    def full_version(self) -> str:
        return f"{self.version}.0.0.0"

    @property
    def window(self) -> tuple[int, int]:
        """A believable window inside that screen."""
        if self.mobile:
            return self.screen
        width, height = self.screen
        return max(1024, int(width * 0.78)), max(700, int(height * 0.86))

    def summary(self, used_by: int = 0) -> dict:
        return {
            "id": self.id,
            "label": self.label,
            "tier": self.tier,
            "tier_label": TIER_LABEL[self.tier],
            "ua": self.ua,
            "brand": self.brand,
            "version": self.version,
            "platform": self.ch_platform or self.platform,
            "mobile": self.mobile,
            "screen": f"{self.screen[0]}×{self.screen[1]}",
            "cores": self.cores,
            "memory": self.memory,
            "gpu": self.webgl_renderer,
            "used_by": used_by,
        }


# --------------------------------------------------------------- ingredients
# Rotated through the versions below so no two neighbours are identical, and
# every combination is one that really exists.

_WIN_SCREENS = [
    ((1920, 1080), 1.0),
    ((1536, 864), 1.25),
    ((1366, 768), 1.0),
    ((2560, 1440), 1.0),
    ((1600, 900), 1.0),
    ((1920, 1200), 1.0),
    ((1440, 900), 1.0),
    ((3840, 2160), 1.5),
]
_WIN_GPUS = [
    ("Google Inc. (NVIDIA)",
     "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
    ("Google Inc. (Intel)",
     "ANGLE (Intel, Intel(R) UHD Graphics 620 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
    ("Google Inc. (AMD)",
     "ANGLE (AMD, AMD Radeon RX 6600 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
    ("Google Inc. (Intel)",
     "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics Direct3D11 vs_5_0 ps_5_0, D3D11)"),
    ("Google Inc. (NVIDIA)",
     "ANGLE (NVIDIA, NVIDIA GeForce GTX 1650 Direct3D11 vs_5_0 ps_5_0, D3D11)"),
]
_MAC_SCREENS = [((1440, 900), 2.0), ((1512, 982), 2.0), ((1680, 1050), 2.0),
                ((1728, 1117), 2.0), ((2560, 1440), 2.0)]
_MAC_GPUS = [
    ("Google Inc. (Apple)",
     "ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)"),
    ("Google Inc. (Apple)",
     "ANGLE (Apple, ANGLE Metal Renderer: Apple M1 Pro, Unspecified Version)"),
    ("Google Inc. (Intel)",
     "ANGLE (Intel, ANGLE Metal Renderer: Intel(R) Iris(TM) Plus Graphics, "
     "Unspecified Version)"),
    ("Google Inc. (Apple)",
     "ANGLE (Apple, ANGLE Metal Renderer: Apple M3, Unspecified Version)"),
]
_LINUX_SCREENS = [((1920, 1080), 1.0), ((2560, 1440), 1.0), ((1600, 900), 1.0)]
_LINUX_GPUS = [
    ("Google Inc. (Intel)",
     "ANGLE (Intel, Mesa Intel(R) UHD Graphics (CML GT2), OpenGL 4.6)"),
    ("Google Inc. (AMD)",
     "ANGLE (AMD, AMD Radeon Graphics (radeonsi, renoir), OpenGL 4.6)"),
    ("Google Inc. (NVIDIA)",
     "ANGLE (NVIDIA Corporation, NVIDIA GeForce RTX 3050/PCIe/SSE2, OpenGL 4.5)"),
]
_ANDROID_SCREENS = [((412, 915), 2.625), ((360, 800), 3.0), ((393, 873), 2.75),
                    ((414, 896), 2.625), ((384, 854), 2.8125)]
_ANDROID_GPUS = [
    ("Qualcomm", "Adreno (TM) 740"),
    ("ARM", "Mali-G715"),
    ("Qualcomm", "Adreno (TM) 660"),
    ("ARM", "Mali-G78 MP20"),
]
_CORES = [4, 6, 8, 8, 12, 16]
_MEMORY = [4, 8, 8, 8]  # deviceMemory never reports more than 8


def _win_ua(version: int) -> str:
    return (
        f"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36"
    )


def _mac_ua(version: int) -> str:
    return (
        f"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36"
    )


def _linux_ua(version: int) -> str:
    return (
        f"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36"
    )


def _android_ua(version: int, device: str = "K", release: int = 10) -> str:
    return (
        f"Mozilla/5.0 (Linux; Android {release}; {device}) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Mobile Safari/537.36"
    )


def _build() -> list[Fingerprint]:
    items: list[Fingerprint] = []
    step = 0

    def rotate(table: Sequence, offset: int):
        return table[offset % len(table)]

    # 01–20 · Windows desktop Chrome 145 → 126.
    for index, version in enumerate(range(145, 125, -1)):
        screen, dpr = rotate(_WIN_SCREENS, index)
        vendor, renderer = rotate(_WIN_GPUS, index)
        items.append(Fingerprint(
            id=f"win-chrome-{version}",
            label=f"ویندوز · کروم {version}",
            tier=SAFE,
            ua=_win_ua(version),
            brand="Google Chrome",
            version=version,
            ch_platform="Windows",
            # 15.0.0 is how Windows 11 reports itself in client hints.
            ch_platform_version="15.0.0" if index < 8 else "10.0.0",
            platform="Win32",
            mobile=False,
            screen=screen,
            dpr=dpr,
            cores=rotate(_CORES, index),
            memory=rotate(_MEMORY, index),
            webgl_vendor=vendor,
            webgl_renderer=renderer,
        ))
        step = index

    # 21–35 · macOS — fourteen Chromes and one Safari.
    mac_versions = [145, 144, 143, 142, 141, 140, 139, 138, 137, 136,
                    None, 135, 134, 133, 132]  # None = Safari
    for index, version in enumerate(mac_versions):
        screen, dpr = rotate(_MAC_SCREENS, index)
        vendor, renderer = rotate(_MAC_GPUS, index)
        if version is None:
            items.append(Fingerprint(
                id="mac-safari-26",
                label="مک · سفاري ۲۶",
                tier=FAIR,
                ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                   "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 "
                   "Safari/605.1.15",
                brand="Safari",
                version=26,
                ch_platform="",
                ch_platform_version="",
                platform="MacIntel",
                mobile=False,
                screen=screen,
                dpr=dpr,
                cores=8,
                memory=None,
                webgl_vendor="Apple Inc.",
                webgl_renderer="Apple GPU",
                vendor="Apple Computer, Inc.",
                has_ua_data=False,
            ))
            continue
        items.append(Fingerprint(
            id=f"mac-chrome-{version}",
            label=f"مک · کروم {version}",
            tier=FAIR,
            ua=_mac_ua(version),
            brand="Google Chrome",
            version=version,
            ch_platform="macOS",
            ch_platform_version="14.6.0" if index < 6 else "13.6.0",
            platform="MacIntel",
            mobile=False,
            screen=screen,
            dpr=dpr,
            cores=rotate(_CORES, index + 2),
            memory=8,
            webgl_vendor=vendor,
            webgl_renderer=renderer,
        ))

    # 36–45 · Linux desktop.
    for index, version in enumerate(range(145, 135, -1)):
        screen, dpr = rotate(_LINUX_SCREENS, index)
        vendor, renderer = rotate(_LINUX_GPUS, index)
        items.append(Fingerprint(
            id=f"linux-chrome-{version}",
            label=f"لینکس · کروم {version}",
            tier=FAIR,
            ua=_linux_ua(version),
            brand="Google Chrome",
            version=version,
            ch_platform="Linux",
            ch_platform_version="6.8.0",
            platform="Linux x86_64",
            mobile=False,
            screen=screen,
            dpr=dpr,
            cores=rotate(_CORES, index + 1),
            memory=8,
            webgl_vendor=vendor,
            webgl_renderer=renderer,
        ))

    # 46–55 · generic Android phones.
    for index, version in enumerate(range(145, 135, -1)):
        items.append(_phone(
            f"android-chrome-{version}", f"اندروید · کروم {version}",
            _android_ua(version), version, "10", "K", index))

    # 56–70 · Samsung, real model codes.
    samsung = [
        ("SM-S938B", 15, 135, "ګلکسي S25 Ultra"),
        ("SM-S928B", 14, 133, "ګلکسي S24 Ultra"),
        ("SM-S918B", 13, 131, "ګلکسي S23 Ultra"),
        ("SM-S908B", 13, 128, "ګلکسي S22 Ultra"),
        ("SM-G991B", 12, 124, "ګلکسي S21"),
        ("SM-G980F", 11, 120, "ګلکسي S20"),
        ("SM-N981B", 11, 118, "ګلکسي Note 20"),
        ("SM-A556B", 14, 130, "ګلکسي A55"),
        ("SM-A546B", 13, 127, "ګلکسي A54"),
        ("SM-A536B", 12, 123, "ګلکسي A53"),
        ("SM-A525F", 11, 119, "ګلکسي A52"),
        ("SM-A515F", 11, 116, "ګلکسي A51"),
        ("SM-G973F", 10, 112, "ګلکسي S10"),
        ("SM-G960F", 10, 108, "ګلکسي S9"),
        ("SM-G950F", 9, 101, "ګلکسي S8"),
    ]
    for index, (model, release, version, name) in enumerate(samsung):
        items.append(_phone(
            f"samsung-{model.lower()}", f"سامسنګ · {name}",
            _android_ua(version, model, release), version, str(release),
            model, index + 3))

    # 71–80 · Google Pixel.
    pixel = [
        ("Pixel 9", 15, 135), ("Pixel 8 Pro", 14, 132), ("Pixel 8", 14, 130),
        ("Pixel 7 Pro", 13, 127), ("Pixel 7", 13, 125), ("Pixel 6 Pro", 12, 121),
        ("Pixel 6", 12, 119), ("Pixel 5", 11, 115), ("Pixel 4", 11, 110),
        ("Pixel 3", 10, 105),
    ]
    for index, (model, release, version) in enumerate(pixel):
        items.append(_phone(
            "pixel-" + model.lower().replace(" ", "-"), f"ګوګل · {model}",
            _android_ua(version, model, release), version, str(release),
            model, index + 1))

    # 81–90 · iPhone, Safari and Chrome-for-iOS (which is Safari underneath).
    iphone = [
        ("18_6", "18.6", None, "18.6"), ("18_6", "18.6", 140, "18.6"),
        ("18_3", "18.3", None, "18.3"), ("18_3", "18.3", 138, "18.3"),
        ("17_6", "17.6", None, "17.6"), ("17_6", "17.6", 130, "17.6"),
        ("16_6", "16.6", None, "16.6"), ("15_6", "15.6", None, "15.6"),
        ("14_8", "14.1", None, "14.8"), ("13_7", "13.1", None, "13.7"),
    ]
    iphone_screens = [((390, 844), 3.0), ((393, 852), 3.0), ((430, 932), 3.0),
                      ((375, 812), 3.0), ((414, 896), 2.0)]
    for index, (os_tag, version_tag, crios, release) in enumerate(iphone):
        engine = (
            f"CriOS/{crios}.0.0.0" if crios else f"Version/{version_tag}"
        )
        screen, dpr = iphone_screens[index % len(iphone_screens)]
        items.append(Fingerprint(
            id=f"iphone-{release.replace('.', '-')}" + (f"-crios{crios}" if crios else ""),
            label=("آیفون · کروم " if crios else "آیفون · سفاري ") + release,
            tier=BOLD,
            ua=(f"Mozilla/5.0 (iPhone; CPU iPhone OS {os_tag} like Mac OS X) "
                f"AppleWebKit/605.1.15 (KHTML, like Gecko) {engine} "
                f"Mobile/15E148 Safari/604.1"),
            brand="Safari",
            version=int(float(version_tag)),
            ch_platform="",
            ch_platform_version="",
            platform="iPhone",
            mobile=True,
            model="iPhone",
            screen=screen,
            dpr=dpr,
            cores=6 if index < 5 else 4,
            memory=None,
            touch=5,
            webgl_vendor="Apple Inc.",
            webgl_renderer="Apple GPU",
            vendor="Apple Computer, Inc.",
            has_ua_data=False,
        ))

    # 91–94 · iPad.
    ipad = [("18_6", "18.6", None), ("18_6", "18.6", 140),
            ("17_6", "17.6", None), ("16_6", "16.6", None)]
    for index, (os_tag, version_tag, crios) in enumerate(ipad):
        engine = f"CriOS/{crios}.0.0.0" if crios else f"Version/{version_tag}"
        items.append(Fingerprint(
            id=f"ipad-{version_tag.replace('.', '-')}" + (f"-crios{crios}" if crios else ""),
            label=("آی‌پډ · کروم " if crios else "آی‌پډ · سفاري ") + version_tag,
            tier=BOLD,
            ua=(f"Mozilla/5.0 (iPad; CPU OS {os_tag} like Mac OS X) "
                f"AppleWebKit/605.1.15 (KHTML, like Gecko) {engine} "
                f"Mobile/15E148 Safari/604.1"),
            brand="Safari",
            version=int(float(version_tag)),
            ch_platform="",
            ch_platform_version="",
            platform="iPad",
            mobile=True,
            model="iPad",
            screen=(820, 1180) if index % 2 == 0 else (1024, 1366),
            dpr=2.0,
            cores=8,
            memory=None,
            touch=5,
            webgl_vendor="Apple Inc.",
            webgl_renderer="Apple GPU",
            vendor="Apple Computer, Inc.",
            has_ua_data=False,
        ))

    # 95–96 · Android tablets — Android, but no "Mobile" in the user agent.
    for index, version in enumerate([145, 140]):
        items.append(Fingerprint(
            id=f"android-tablet-{version}",
            label=f"اندروید ټابلیټ · کروم {version}",
            tier=BOLD,
            ua=(f"Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
                f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36"),
            brand="Google Chrome",
            version=version,
            ch_platform="Android",
            ch_platform_version="10.0.0",
            platform="Linux armv8l",
            mobile=False,  # a tablet reports mobile=false in client hints
            model="K",
            screen=(800, 1280),
            dpr=2.0,
            cores=8,
            memory=4,
            touch=5,
            webgl_vendor="ARM",
            webgl_renderer="Mali-G710",
        ))

    # 97–98 · ChromeOS.
    for index, version in enumerate([145, 140]):
        items.append(Fingerprint(
            id=f"chromeos-{version}",
            label=f"کروم‌بوک · کروم {version}",
            tier=FAIR,
            ua=(f"Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 "
                f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36"),
            brand="Google Chrome",
            version=version,
            ch_platform="Chrome OS",
            ch_platform_version="14541.0.0",
            platform="Linux x86_64",
            mobile=False,
            screen=(1920, 1080) if index == 0 else (1366, 768),
            dpr=1.0,
            cores=8,
            memory=8,
            webgl_vendor="Google Inc. (Intel)",
            webgl_renderer="ANGLE (Intel, Mesa Intel(R) UHD Graphics, OpenGL 4.6)",
        ))

    # 99–100 · Edge, on Windows and on Android.
    items.append(Fingerprint(
        id="win-edge-143",
        label="ویندوز · اېج ۱۴۳",
        tier=SAFE,
        ua=("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"),
        brand="Microsoft Edge",
        version=143,
        ch_platform="Windows",
        ch_platform_version="15.0.0",
        platform="Win32",
        mobile=False,
        screen=(1920, 1080),
        dpr=1.0,
        cores=8,
        memory=8,
        webgl_vendor=_WIN_GPUS[1][0],
        webgl_renderer=_WIN_GPUS[1][1],
    ))
    items.append(Fingerprint(
        id="android-edge-141",
        label="اندروید · اېج ۱۴۱",
        tier=BOLD,
        ua=("Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36 "
            "EdgA/141.0.0.0"),
        brand="Microsoft Edge",
        version=141,
        ch_platform="Android",
        ch_platform_version="10.0.0",
        platform="Linux armv8l",
        mobile=True,
        model="K",
        screen=(412, 915),
        dpr=2.625,
        cores=8,
        memory=4,
        touch=5,
        webgl_vendor="Qualcomm",
        webgl_renderer="Adreno (TM) 740",
    ))
    return items


def _phone(fid: str, label: str, ua: str, version: int, release: str,
           model: str, index: int) -> Fingerprint:
    screen, dpr = _ANDROID_SCREENS[index % len(_ANDROID_SCREENS)]
    vendor, renderer = _ANDROID_GPUS[index % len(_ANDROID_GPUS)]
    return Fingerprint(
        id=fid,
        label=label,
        tier=BOLD,
        ua=ua,
        brand="Google Chrome",
        version=version,
        ch_platform="Android",
        ch_platform_version=f"{release}.0.0",
        platform="Linux armv8l",
        mobile=True,
        model=model,
        screen=screen,
        dpr=dpr,
        cores=8,
        memory=4 if index % 2 else 8,
        touch=5,
        webgl_vendor=vendor,
        webgl_renderer=renderer,
    )


CATALOGUE: list[Fingerprint] = _build()
BY_ID: dict[str, Fingerprint] = {item.id: item for item in CATALOGUE}


def all_profiles(tier: str | None = None) -> list[Fingerprint]:
    if tier:
        return [f for f in CATALOGUE if f.tier == tier]
    return list(CATALOGUE)


def get(fingerprint_id: str) -> Fingerprint | None:
    return BY_ID.get(fingerprint_id)


def new_seed() -> int:
    """The account's own pinch of noise, fixed for its lifetime."""
    return random.getrandbits(31)


def stable_seed(account_id: str) -> int:
    """A seed derived from the id — same account, same machine, always."""
    digest = hashlib.sha256(account_id.encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big") & 0x7FFFFFFF


def assign(
    taken: Iterable[str] = (),
    account_id: str = "",
    real_version: int | None = None,
    allow_tiers: Sequence[str] = (SAFE, FAIR),
) -> str:
    """Pick the identity for a new account.

    Three rules, in order:

    1. **Never hand out a phone.** A desktop browser wearing a phone's user
       agent is caught by the first page that measures the window.
    2. **Stay near the browser we really have.** Claiming Chrome 108 while
       running Chrome 145 is detectable in one line of JavaScript — the page
       simply asks for a feature that only 145 has. Identities within a few
       versions of the installed browser are preferred.
    3. **Spread out.** Of the identities that pass, the least used one wins;
       between equals the account's own id decides, so the choice is
       reproducible.
    """
    used: dict[str, int] = {}
    for item in taken:
        used[item] = used.get(item, 0) + 1

    candidates = [f for f in CATALOGUE if f.tier in allow_tiers]
    if not candidates:
        candidates = list(CATALOGUE)

    tier_rank = {SAFE: 0, FAIR: 1, BOLD: 2}
    tiebreak = stable_seed(account_id or "")

    def score(item: Fingerprint) -> tuple:
        # Close to the browser we really have; when that is not known, newest
        # first — an up-to-date browser is the ordinary case in the wild.
        distance = (
            abs(item.version - real_version) if real_version
            else max(0, 200 - item.version)
        )
        return (
            used.get(item.id, 0),          # least used first
            tier_rank.get(item.tier, 3),   # then the safest tier
            distance,                      # then closest to the real browser
            (hash(item.id) ^ tiebreak) & 0xFFFF,
        )

    return min(candidates, key=score).id


def ensure(account, real_version: int | None = None, taken: Iterable[str] = ()) -> bool:
    """Give an account an identity if it has none. True when one was added."""
    changed = False
    if not getattr(account, "fingerprint_id", "") or account.fingerprint_id not in BY_ID:
        account.fingerprint_id = assign(
            taken, account.id, real_version=real_version
        )
        changed = True
    if not getattr(account, "fingerprint_seed", 0):
        account.fingerprint_seed = stable_seed(account.id)
        changed = True
    return changed
