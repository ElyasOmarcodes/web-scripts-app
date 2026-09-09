/*
 * WebScripts in-page recorder.
 *
 * Injected into every document (main frame and each reachable iframe) by the
 * Python side. It listens to user interaction, builds a ranked list of
 * locator candidates for each touched element and buffers the events. Python
 * drains the buffer every few hundred milliseconds via __WS_RECORDER__.drain().
 *
 * The script re-injects itself after every navigation, so it must be
 * idempotent and must never throw into the page.
 */
(function () {
  "use strict";

  if (window.__WS_RECORDER__ && window.__WS_RECORDER__.alive) {
    return "already";
  }

  var MAX_EVENTS = 2000;
  var MAX_TEXT = 60;

  var state = {
    alive: true,
    events: [],
    pending: null, // {el, value} for the field currently being typed into
    lastScroll: 0,
    lastClick: { value: "", ts: 0 },
    opts: { captureScroll: false }
  };
  window.__WS_RECORDER__ = state;

  state.drain = function () {
    var out = state.events;
    state.events = [];
    return out;
  };

  /* ---------------------------------------------------------------- utils */

  function cssEscape(s) {
    if (window.CSS && CSS.escape) {
      try { return CSS.escape(s); } catch (e) { /* fall through */ }
    }
    return String(s).replace(/([^a-zA-Z0-9_-])/g, "\\$1");
  }

  // Quote a string for use inside an XPath expression.
  function xq(s) {
    s = String(s);
    if (s.indexOf('"') === -1) return '"' + s + '"';
    if (s.indexOf("'") === -1) return "'" + s + "'";
    var parts = s.split('"');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      out.push('"' + parts[i] + '"');
      if (i < parts.length - 1) out.push("'\"'");
    }
    return "concat(" + out.join(",") + ")";
  }

  function norm(s) {
    return String(s == null ? "" : s).replace(/\s+/g, " ").trim();
  }

  function textOf(el) {
    var t = norm(el.innerText || el.textContent || "");
    return t.length > MAX_TEXT ? "" : t;
  }

  // Auto-generated ids (React, Ember, Facebook, MUI ...) change on every load
  // and are useless as locators.
  function isStableId(id) {
    if (!id || id.length > 60) return false;
    if (/^\d/.test(id)) return false;
    if (/\d{4,}/.test(id)) return false;
    if (/^(:r|r:|ember|mui-|radix-|headlessui|react-aria|js_|jsc_|u_|__)/i.test(id)) return false;
    if (/^[a-z0-9]{16,}$/i.test(id)) return false;
    return true;
  }

  function isStableClass(cls) {
    if (!cls || cls.length < 3 || cls.length > 40) return false;
    if (/\d{3,}/.test(cls)) return false;
    // Emotion / styled-components / atomic css hashes.
    if (/^(css-|sc-|jsx-|x[a-z0-9]{5,}$)/.test(cls)) return false;
    if (/^[a-z0-9]{8,}$/.test(cls) && !/[-_]/.test(cls)) return false;
    return true;
  }

  function cssFirst(sel) {
    try { return document.querySelector(sel); } catch (e) { return null; }
  }

  function xpathFirst(xp) {
    try {
      return document.evaluate(xp, document, null, 9, null).singleNodeValue;
    } catch (e) { return null; }
  }

  function resolvesTo(target, el) {
    var found = target.type === "css" ? cssFirst(target.value) : xpathFirst(target.value);
    return found === el;
  }

  /* ------------------------------------------------------------ locators */

  function cssPath(el) {
    var parts = [];
    var node = el;
    var depth = 0;
    while (node && node.nodeType === 1 && depth < 10) {
      if (node.tagName === "HTML" || node.tagName === "BODY") break;
      if (isStableId(node.id)) {
        parts.unshift("#" + cssEscape(node.id));
        break;
      }
      var sel = node.tagName.toLowerCase();
      var parent = node.parentElement;
      if (parent) {
        var same = [];
        for (var i = 0; i < parent.children.length; i++) {
          if (parent.children[i].tagName === node.tagName) same.push(parent.children[i]);
        }
        if (same.length > 1) {
          sel += ":nth-of-type(" + (same.indexOf(node) + 1) + ")";
        }
      }
      parts.unshift(sel);
      node = parent;
      depth++;
    }
    return parts.join(" > ");
  }

  function absXPath(el) {
    var parts = [];
    var node = el;
    var depth = 0;
    while (node && node.nodeType === 1 && depth < 20) {
      var index = 1;
      var sib = node.previousElementSibling;
      while (sib) {
        if (sib.tagName === node.tagName) index++;
        sib = sib.previousElementSibling;
      }
      parts.unshift(node.tagName.toLowerCase() + "[" + index + "]");
      node = node.parentElement;
      depth++;
    }
    return "/" + parts.join("/");
  }

  function attrTarget(el, attr, kind) {
    var v = el.getAttribute && el.getAttribute(attr);
    if (!v) return null;
    v = norm(v);
    if (!v || v.length > 80) return null;
    return {
      type: "css",
      value: el.tagName.toLowerCase() + "[" + attr + "=" + JSON.stringify(v) + "]",
      kind: kind
    };
  }

  // Ordered from most to least robust. Python keeps the order.
  function buildTargets(el) {
    var out = [];
    var tag = el.tagName.toLowerCase();

    ["data-testid", "data-test-id", "data-test", "data-qa", "data-cy"].forEach(function (a) {
      var t = attrTarget(el, a, "testid");
      if (t) out.push({ type: "css", value: "[" + a + "=" + JSON.stringify(norm(el.getAttribute(a))) + "]", kind: "testid" });
    });

    if (isStableId(el.id)) {
      out.push({ type: "css", value: "#" + cssEscape(el.id), kind: "id" });
    }

    var name = el.getAttribute && el.getAttribute("name");
    if (name) out.push({ type: "css", value: tag + "[name=" + JSON.stringify(name) + "]", kind: "name" });

    var aria = attrTarget(el, "aria-label", "aria");
    if (aria) out.push(aria);

    var placeholder = attrTarget(el, "placeholder", "placeholder");
    if (placeholder) out.push(placeholder);

    var title = attrTarget(el, "title", "title");
    if (title) out.push(title);

    if (tag === "img") {
      var alt = attrTarget(el, "alt", "alt");
      if (alt) out.push(alt);
    }

    if (tag === "input" && el.type && ["submit", "button", "reset"].indexOf(el.type) >= 0 && el.value) {
      out.push({ type: "css", value: 'input[value=' + JSON.stringify(norm(el.value)) + "]", kind: "value" });
    }

    var role = el.getAttribute && el.getAttribute("role");
    var text = textOf(el);

    if (text) {
      if (role) {
        out.push({
          type: "xpath",
          value: "//*[@role=" + xq(role) + " and normalize-space(.)=" + xq(text) + "]",
          kind: "role-text"
        });
      }
      if (["a", "button", "span", "div", "li", "label", "h1", "h2", "h3", "summary"].indexOf(tag) >= 0) {
        out.push({
          type: "xpath",
          value: "//" + tag + "[normalize-space(.)=" + xq(text) + "]",
          kind: "text"
        });
      }
      out.push({
        type: "xpath",
        value: "//*[normalize-space(text())=" + xq(text) + "]",
        kind: "any-text"
      });
    }

    // A stable class scoped to the tag can be a decent mid-tier fallback.
    if (el.classList && el.classList.length) {
      for (var i = 0; i < el.classList.length && i < 4; i++) {
        var cls = el.classList[i];
        if (isStableClass(cls)) {
          out.push({ type: "css", value: tag + "." + cssEscape(cls), kind: "class" });
          break;
        }
      }
    }

    // Keep only candidates that actually resolve back to this element.
    var verified = [];
    var seen = {};
    for (var j = 0; j < out.length; j++) {
      var t = out[j];
      if (seen[t.type + "|" + t.value]) continue;
      seen[t.type + "|" + t.value] = 1;
      if (resolvesTo(t, el)) verified.push(t);
    }

    // Structural fallbacks always come last.
    var path = cssPath(el);
    if (path && !seen["css|" + path]) verified.push({ type: "css", value: path, kind: "path" });
    var abs = absXPath(el);
    if (abs) verified.push({ type: "xpath", value: abs, kind: "abs" });

    return verified.slice(0, 8);
  }

  // <label for="..."> or a wrapping <label> gives a control its human name.
  function labelledBy(el) {
    try {
      if (el.labels && el.labels.length) return textOf(el.labels[0]);
      if (el.id) {
        var lab = document.querySelector("label[for=" + JSON.stringify(el.id) + "]");
        if (lab) return textOf(lab);
      }
    } catch (e) { /* ignore */ }
    return "";
  }

  function labelOf(el) {
    if (!el || !el.tagName) return "";
    var tag = el.tagName.toLowerCase();
    // For form controls the text content is the option/placeholder soup, not
    // a name a human would recognise.
    var isControl = ["input", "select", "textarea"].indexOf(tag) >= 0;
    var candidates = [
      el.getAttribute && el.getAttribute("aria-label"),
      el.getAttribute && el.getAttribute("placeholder"),
      isControl ? "" : textOf(el),
      el.getAttribute && el.getAttribute("title"),
      el.getAttribute && el.getAttribute("name"),
      isControl ? labelledBy(el) : "",
      isStableId(el.id) ? el.id : "",
      tag
    ];
    for (var i = 0; i < candidates.length; i++) {
      var c = norm(candidates[i]);
      if (c) return c.length > 48 ? c.slice(0, 48) + "…" : c;
    }
    return el.tagName.toLowerCase();
  }

  /* -------------------------------------------------------------- events */

  function push(action, el, extra) {
    try {
      var ev = {
        action: action,
        ts: Date.now(),
        url: location.href,
        targets: el ? buildTargets(el) : [],
        label: el ? labelOf(el) : "",
        tag: el && el.tagName ? el.tagName.toLowerCase() : null
      };
      if (extra) {
        for (var k in extra) {
          if (Object.prototype.hasOwnProperty.call(extra, k)) ev[k] = extra[k];
        }
      }
      state.events.push(ev);
      if (state.events.length > MAX_EVENTS) state.events.shift();
    } catch (e) {
      /* never break the page being recorded */
    }
  }

  function isTextInput(el) {
    if (!el || !el.tagName) return false;
    var tag = el.tagName.toLowerCase();
    if (tag === "textarea") return true;
    if (el.isContentEditable) return true;
    if (tag !== "input") return false;
    var type = (el.getAttribute("type") || "text").toLowerCase();
    return ["text", "password", "email", "search", "tel", "url", "number", "date", "time"].indexOf(type) >= 0;
  }

  function valueOf(el) {
    if (el.isContentEditable) return norm(el.innerText || el.textContent || "");
    return el.value == null ? "" : String(el.value);
  }

  function flushPending() {
    var p = state.pending;
    state.pending = null;
    if (!p || !p.el) return;
    try {
      if (!document.contains(p.el)) return;
      var isSecret = p.el.tagName.toLowerCase() === "input" &&
        (p.el.getAttribute("type") || "").toLowerCase() === "password";
      var v = valueOf(p.el);
      if (!v && !isSecret) return;
      push("type", p.el, { value: isSecret ? "" : v, secret: isSecret });
    } catch (e) { /* ignore */ }
  }

  // The element the user meant to click: a nested <span> inside a button
  // should be recorded as the button.
  var CLICKABLE = 'a,button,input,select,textarea,label,summary,[role="button"],' +
    '[role="menuitem"],[role="tab"],[role="link"],[role="option"],[role="checkbox"],' +
    '[role="switch"],[role="menuitemcheckbox"],[role="radio"],[onclick]';

  function pick(node) {
    if (!node || node.nodeType !== 1) {
      node = node && node.parentElement ? node.parentElement : document.body;
    }
    try {
      var better = node.closest ? node.closest(CLICKABLE) : null;
      if (better) return better;
    } catch (e) { /* ignore */ }
    return node;
  }

  document.addEventListener("click", function (e) {
    if (e.button && e.button !== 0) return;
    var el = pick(e.target);
    if (state.pending && state.pending.el !== el) flushPending();
    // Opening a dropdown is not a step of its own — the "change" handler
    // records the actual choice.
    if (el.tagName && el.tagName.toLowerCase() === "select") return;
    var key = (el.tagName || "") + "|" + labelOf(el);
    var now = Date.now();
    // Some frameworks fire the same click twice (label + input).
    if (key === state.lastClick.value && now - state.lastClick.ts < 350) return;
    state.lastClick = { value: key, ts: now };
    push("click", el, {});
  }, true);

  document.addEventListener("input", function (e) {
    var el = e.target;
    if (!isTextInput(el)) return;
    if (state.pending && state.pending.el !== el) flushPending();
    state.pending = { el: el, value: valueOf(el) };
  }, true);

  document.addEventListener("change", function (e) {
    var el = e.target;
    if (!el || !el.tagName) return;
    if (el.tagName.toLowerCase() === "select") {
      flushPending();
      var opt = el.options && el.options[el.selectedIndex];
      push("select", el, {
        value: opt ? norm(opt.text) : "",
        optionValue: el.value == null ? "" : String(el.value)
      });
      return;
    }
    if (isTextInput(el) && state.pending && state.pending.el === el) flushPending();
  }, true);

  document.addEventListener("blur", function (e) {
    if (state.pending && state.pending.el === e.target) flushPending();
  }, true);

  document.addEventListener("keydown", function (e) {
    var k = e.key;
    if (k === "Enter") {
      flushPending();
      push("press_key", e.target, { value: "ENTER" });
    } else if (k === "Escape") {
      flushPending();
      push("press_key", e.target, { value: "ESCAPE" });
    } else if (k === "Tab") {
      flushPending();
    }
  }, true);

  window.addEventListener("scroll", function () {
    if (!state.opts.captureScroll) return;
    var now = Date.now();
    if (now - state.lastScroll < 800) return;
    state.lastScroll = now;
    push("scroll", null, { value: String(Math.round(window.scrollY || 0)) });
  }, true);

  window.addEventListener("beforeunload", flushPending, true);

  /* ------------------------------------------------------------- overlay */

  if (window.top === window) {
    try {
      var badge = document.getElementById("__ws_badge__");
      if (!badge) {
        badge = document.createElement("div");
        badge.id = "__ws_badge__";
        badge.textContent = "● WebScripts — ثبتول روان دي";
        badge.setAttribute("style", [
          "position:fixed", "z-index:2147483647", "top:12px", "right:12px",
          "background:#c62828", "color:#fff", "font:600 12px/1.6 Segoe UI,Tahoma,sans-serif",
          "padding:6px 12px", "border-radius:999px", "pointer-events:none",
          "box-shadow:0 2px 10px rgba(0,0,0,.35)", "direction:rtl"
        ].join(";"));
        (document.body || document.documentElement).appendChild(badge);
      }
    } catch (e) { /* ignore */ }
  }

  return "installed";
})();
