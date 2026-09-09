# PyInstaller spec: bundles the Python backend into one webscripts-backend.exe
#
#   pyinstaller packaging/webscripts-backend.spec --noconfirm
#
# Paths inside a spec are resolved relative to the SPEC FILE, never to the
# working directory, so everything below is anchored on SPECPATH.
#
# The result needs no Python on the target machine. Selenium Manager (shipped
# inside the selenium package) still downloads the matching browser driver on
# first run, so the machine needs internet access once.

import os

from PyInstaller.utils.hooks import collect_all

BACKEND = os.path.abspath(os.path.join(SPECPATH, os.pardir, "backend"))  # noqa: F821

datas = []
binaries = []
hiddenimports = [
    "uvicorn.logging",
    "uvicorn.loops.auto",
    "uvicorn.loops.asyncio",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.http.h11_impl",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.protocols.websockets.websockets_impl",
    "uvicorn.lifespan.on",
]

# selenium ships the selenium-manager binary as package data; the web stack
# resolves a lot of its modules dynamically.
for package in (
    "selenium",
    "uvicorn",
    "fastapi",
    "starlette",
    "pydantic",
    "pydantic_core",
    "anyio",
    "h11",
    "websockets",
):
    package_datas, package_binaries, package_hidden = collect_all(package)
    datas += package_datas
    binaries += package_binaries
    hiddenimports += package_hidden

# The in-page recorder is read from disk at runtime.
datas += [(os.path.join(BACKEND, "webscripts", "js", "recorder.js"), "webscripts/js")]

a = Analysis(  # noqa: F821
    [os.path.join(BACKEND, "run_server.py")],
    pathex=[BACKEND],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "numpy", "PIL", "pytest"],
    noarchive=False,
)

pyz = PYZ(a.pure)  # noqa: F821

exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="webscripts-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    # No console window: the desktop app displays the log stream instead.
    console=False,
    disable_windowed_traceback=False,
)
