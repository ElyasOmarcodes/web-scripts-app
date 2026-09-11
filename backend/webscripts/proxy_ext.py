"""Making Chrome use a proxy that asks for a username and password.

`--proxy-server=http://user:pass@host:port` does not work: Chrome drops the
credentials and shows a login box instead, which nobody is there to fill in.
The way that does work is a tiny extension — it points the browser at the
proxy and answers the authentication challenge from the background.

The extension is written into a throwaway directory next to the account's
profile and removed when the browser closes. It contains the proxy password,
so the directory is created with owner-only permissions.
"""

from __future__ import annotations

import json
import shutil
import stat
import tempfile
from pathlib import Path

from .proxies import Proxy

MANIFEST = {
    "name": "WebScripts proxy",
    "version": "1.0.0",
    "manifest_version": 3,
    "permissions": ["proxy", "webRequest", "webRequestAuthProvider", "storage"],
    "host_permissions": ["<all_urls>"],
    "background": {"service_worker": "background.js"},
}

BACKGROUND = """
// Point the browser at the proxy…
chrome.proxy.settings.set({
  value: {
    mode: "fixed_servers",
    rules: {
      singleProxy: {scheme: %(scheme)s, host: %(host)s, port: %(port)d},
      // Local addresses never go through the proxy.
      bypassList: ["localhost", "127.0.0.1"]
    }
  },
  scope: "regular"
});

// …and answer its login prompt from here, so no dialog ever appears.
chrome.webRequest.onAuthRequired.addListener(
  function (details) {
    return {authCredentials: {username: %(username)s, password: %(password)s}};
  },
  {urls: ["<all_urls>"]},
  ["blocking"]
);
"""


def build(proxy: Proxy, parent: Path | None = None) -> Path:
    """Write the extension and return its directory."""
    directory = Path(
        tempfile.mkdtemp(prefix="ws-proxy-", dir=str(parent) if parent else None)
    )
    directory.chmod(stat.S_IRWXU)  # the password lives in here

    scheme = "http" if proxy.scheme in {"http", "https"} else proxy.scheme
    (directory / "manifest.json").write_text(
        json.dumps(MANIFEST, indent=2), encoding="utf-8"
    )
    (directory / "background.js").write_text(
        BACKGROUND % {
            "scheme": json.dumps(scheme),
            "host": json.dumps(proxy.host),
            "port": proxy.port,
            "username": json.dumps(proxy.username),
            "password": json.dumps(proxy.password),
        },
        encoding="utf-8",
    )
    return directory


def clean(directory: Path | str | None) -> None:
    if not directory:
        return
    shutil.rmtree(str(directory), ignore_errors=True)
