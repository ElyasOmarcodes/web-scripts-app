"""Putting an account's identity on a running browser.

:mod:`fingerprints` decides *which* device an account is. This module makes
the browser actually be it, in two layers:

**Before the page loads** — CDP overrides. These change what the browser sends
on the wire: the user agent, the ``Sec-CH-UA`` client hints that go with it,
the ``Accept-Language`` header, the timezone and the locale. Anything done
here is done by the browser itself, so there is nothing for a page to catch.

**Inside the page** — one script injected ahead of every document. It covers
the readings that live only in JavaScript: the screen, the core and memory
counts, the graphics card name, and the tiny per-machine noise in canvas and
audio. Each account's noise comes from its own seed, so two accounts that
share a device model still do not look like one computer, and every run of the
same account looks like the same computer.

Order matters: the CDP overrides and the script always agree, because both are
generated from the same :class:`~webscripts.fingerprints.Fingerprint`.
"""

from __future__ import annotations

import json
from typing import Any

from . import geo
from .fingerprints import Fingerprint

# Standard screens, used when the real window turns out to be wider than the
# screen the identity claims — a window larger than its own screen is
# impossible, and impossible is what gets noticed.
_LADDER = [(1280, 720), (1366, 768), (1440, 900), (1536, 864), (1600, 900),
           (1920, 1080), (1920, 1200), (2560, 1440), (3840, 2160)]


def brands(fingerprint: Fingerprint) -> list[dict[str, str]]:
    """The ``Sec-CH-UA`` brand list Chrome would send for this version.

    Chrome mixes in one deliberately silly entry ("Not;A=Brand") to stop sites
    hard-coding the list. Ours is derived from the version, so it is stable
    for an account instead of changing every launch.
    """
    if not fingerprint.has_ua_data:
        return []
    version = str(fingerprint.version)
    grease = ["Not;A=Brand", "Not_A Brand", "Not(A:Brand", "Not.A/Brand"]
    listed = [
        {"brand": grease[fingerprint.version % len(grease)], "version": "99"},
        {"brand": "Chromium", "version": version},
    ]
    if fingerprint.brand != "Chromium":
        listed.append({"brand": fingerprint.brand, "version": version})
    return listed


def metadata(fingerprint: Fingerprint) -> dict[str, Any]:
    full = [
        {"brand": item["brand"],
         "version": "99.0.0.0" if item["brand"].startswith("Not")
                    else fingerprint.full_version}
        for item in brands(fingerprint)
    ]
    return {
        "brands": brands(fingerprint),
        "fullVersionList": full,
        "platform": fingerprint.ch_platform,
        "platformVersion": fingerprint.ch_platform_version,
        "architecture": "" if fingerprint.mobile else "x86",
        "model": fingerprint.model,
        "mobile": fingerprint.mobile,
        "bitness": "" if fingerprint.mobile else "64",
        "wow64": False,
    }


def languages_for(fingerprint: Fingerprint, country: str = "") -> tuple[str, ...]:
    """The language list: the proxy's country first, the device's own after."""
    return geo.languages_for(country) or fingerprint.languages


def fit_screen(fingerprint: Fingerprint, window: tuple[int, int] | None) -> tuple[int, int]:
    """Grow the claimed screen if the real window would not fit inside it."""
    width, height = fingerprint.screen
    if not window:
        return width, height
    need_w, need_h = window
    if need_w <= width and need_h + 90 <= height:
        return width, height
    for candidate in _LADDER:
        if candidate[0] >= need_w and candidate[1] >= need_h + 90:
            return candidate
    return max(width, need_w), max(height, need_h + 90)


def script(
    fingerprint: Fingerprint,
    seed: int,
    country: str = "",
    window: tuple[int, int] | None = None,
) -> str:
    """The JavaScript that makes the page see this device."""
    width, height = fit_screen(fingerprint, window)
    config = {
        "seed": int(seed) & 0x7FFFFFFF,
        "platform": fingerprint.platform,
        "vendor": fingerprint.vendor,
        "languages": list(languages_for(fingerprint, country)),
        "cores": fingerprint.cores,
        "memory": fingerprint.memory,
        "touch": fingerprint.touch,
        "width": width,
        "height": height,
        "dpr": fingerprint.dpr,
        "glVendor": fingerprint.webgl_vendor,
        "glRenderer": fingerprint.webgl_renderer,
        "hasUaData": fingerprint.has_ua_data,
    }
    return "const __WS_ID__ = " + json.dumps(config, ensure_ascii=False) + ";\n" + _BODY


_BODY = r"""
(() => {
  const cfg = __WS_ID__;

  // A repeatable random stream. The same account always gets the same
  // sequence, so its noise never changes between runs.
  let state = cfg.seed >>> 0;
  const rand = () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  const hide = (object, name, value) => {
    try {
      Object.defineProperty(object, name, {get: () => value, configurable: true});
    } catch (e) {}
  };

  // ---------------------------------------------------------- the machine
  hide(navigator, 'platform', cfg.platform);
  hide(navigator, 'vendor', cfg.vendor);
  hide(navigator, 'hardwareConcurrency', cfg.cores);
  hide(navigator, 'maxTouchPoints', cfg.touch);
  hide(navigator, 'languages', Object.freeze(cfg.languages.slice()));
  if (cfg.memory === null) {
    try { delete Navigator.prototype.deviceMemory; } catch (e) {}
  } else {
    hide(navigator, 'deviceMemory', cfg.memory);
  }
  // Safari has no client hints object at all. Leaving Chrome's in place
  // while the user agent says Safari is the giveaway, not the absence.
  if (!cfg.hasUaData) {
    try { delete Navigator.prototype.userAgentData; } catch (e) {}
    try { hide(navigator, 'userAgentData', undefined); } catch (e) {}
  }

  // ------------------------------------------------------------ the screen
  hide(screen, 'width', cfg.width);
  hide(screen, 'height', cfg.height);
  hide(screen, 'availWidth', cfg.width);
  // The taskbar, where a real desktop has one.
  hide(screen, 'availHeight', cfg.touch ? cfg.height : cfg.height - 40);
  hide(screen, 'colorDepth', 24);
  hide(screen, 'pixelDepth', 24);
  try {
    Object.defineProperty(window, 'devicePixelRatio',
      {get: () => cfg.dpr, configurable: true});
  } catch (e) {}

  // -------------------------------------------------------------- graphics
  const GL_VENDOR = 0x1F00, GL_RENDERER = 0x1F01;
  const UNMASKED_VENDOR = 0x9245, UNMASKED_RENDERER = 0x9246;
  const patchGl = (proto) => {
    if (!proto || !proto.getParameter) return;
    const original = proto.getParameter;
    proto.getParameter = function (parameter) {
      if (parameter === UNMASKED_VENDOR || parameter === GL_VENDOR) return cfg.glVendor;
      if (parameter === UNMASKED_RENDERER || parameter === GL_RENDERER) return cfg.glRenderer;
      return original.apply(this, arguments);
    };
  };
  patchGl(window.WebGLRenderingContext && WebGLRenderingContext.prototype);
  patchGl(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);

  // ---------------------------------------------------------------- canvas
  // Two computers never draw text to the pixel identically. A shift far below
  // one pixel is invisible on screen but moves the image's checksum, and it
  // moves it the same way every time for this account.
  const drift = (rand() - 0.5) * 0.0009;
  const shiftText = (proto, name) => {
    if (!proto || !proto[name]) return;
    const original = proto[name];
    proto[name] = function (text, x, y, ...rest) {
      return original.call(this, text, x + drift, y + drift, ...rest);
    };
  };
  shiftText(window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype, 'fillText');
  shiftText(window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype, 'strokeText');

  if (window.CanvasRenderingContext2D) {
    const readPixels = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function (...args) {
      const image = readPixels.apply(this, args);
      try {
        let noise = cfg.seed >>> 0;
        const data = image.data;
        // A handful of channels, one step up or down: under the eye, over the
        // checksum.
        for (let i = 0; i < data.length; i += 5333) {
          noise = (noise * 1664525 + 1013904223) >>> 0;
          data[i] = Math.max(0, Math.min(255, data[i] + ((noise & 1) ? 1 : -1)));
        }
      } catch (e) {}
      return image;
    };
  }

  // ----------------------------------------------------------------- audio
  if (window.AudioBuffer) {
    const channel = AudioBuffer.prototype.getChannelData;
    AudioBuffer.prototype.getChannelData = function (...args) {
      const data = channel.apply(this, args);
      try {
        const amount = (cfg.seed % 1000) * 1e-10;
        for (let i = 0; i < data.length; i += 997) data[i] += amount;
      } catch (e) {}
      return data;
    };
  }

  // ---------------------------------------------------------------- WebRTC
  // A proxy carries TCP. WebRTC opens its own UDP path straight out of the
  // machine, and the address it finds there is the real one — the single
  // widest hole under a proxy. Local and server-reflexive candidates are
  // dropped before any page can read them.
  if (window.RTCPeerConnection) {
    const leaks = (candidate) => {
      const text = (candidate && candidate.candidate) || '';
      return text.includes(' host ') || text.includes(' srflx ') ||
             text.includes('.local');
    };
    const Original = window.RTCPeerConnection;
    const Patched = function (...args) {
      const connection = new Original(...args);
      const add = connection.addEventListener.bind(connection);
      connection.addEventListener = function (type, listener, ...rest) {
        if (type === 'icecandidate' && typeof listener === 'function') {
          return add(type, (event) => {
            if (event && event.candidate && leaks(event.candidate)) return;
            return listener(event);
          }, ...rest);
        }
        return add(type, listener, ...rest);
      };
      Object.defineProperty(connection, 'onicecandidate', {
        configurable: true,
        set(listener) {
          connection.addEventListener('icecandidate', listener);
        },
        get() { return null; },
      });
      return connection;
    };
    Patched.prototype = Original.prototype;
    window.RTCPeerConnection = Patched;
    if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = Patched;
  }

  // ------------------------------------------------------------ where I am
  // The browser's location comes from the device's GPS or WiFi, never from the
  // proxy — so answering it would hand over the real city. It is refused,
  // exactly as it is for the many people who never allow it.
  if (navigator.geolocation) {
    const denied = (onError) => {
      if (typeof onError === 'function') {
        onError({code: 1, message: 'User denied Geolocation',
                 PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3});
      }
    };
    navigator.geolocation.getCurrentPosition = (_ok, onError) => denied(onError);
    navigator.geolocation.watchPosition = (_ok, onError) => { denied(onError); return 0; };
  }
})();
"""


def apply(
    driver,
    fingerprint: Fingerprint,
    seed: int,
    country: str = "",
    city: str = "",
    timezone: str = "",
) -> dict[str, Any]:
    """Dress the browser as this device. Returns what was actually applied."""
    applied: dict[str, Any] = {"fingerprint": fingerprint.id, "timezone": "",
                               "languages": [], "failed": []}
    languages = languages_for(fingerprint, country)
    applied["languages"] = list(languages)

    try:
        window = tuple(driver.get_window_size().values())[:2]  # type: ignore[assignment]
    except Exception:  # noqa: BLE001 - headless, or a driver without it
        window = None

    def cdp(command: str, params: dict[str, Any]) -> bool:
        try:
            driver.execute_cdp_cmd(command, params)
            return True
        except Exception:  # noqa: BLE001 - an override we can live without
            applied["failed"].append(command)
            return False

    override: dict[str, Any] = {
        "userAgent": fingerprint.ua,
        "acceptLanguage": geo.accept_language(languages),
        "platform": fingerprint.platform,
    }
    if fingerprint.has_ua_data:
        override["userAgentMetadata"] = metadata(fingerprint)
    cdp("Network.setUserAgentOverride", override)

    zone = timezone or geo.timezone_for(country, city)
    if zone and cdp("Emulation.setTimezoneOverride", {"timezoneId": zone}):
        applied["timezone"] = zone
    if languages:
        cdp("Emulation.setLocaleOverride", {"locale": languages[0]})
    if fingerprint.touch:
        cdp("Emulation.setTouchEmulationEnabled",
            {"enabled": True, "maxTouchPoints": fingerprint.touch})

    cdp("Page.addScriptToEvaluateOnNewDocument",
        {"source": script(fingerprint, seed, country, window)})
    return applied
