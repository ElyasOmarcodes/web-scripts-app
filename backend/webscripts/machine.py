"""What this computer can take, and what a task will cost it.

The user picks how many accounts run at the same time. Each one is a real
browser, so the honest answer to "can my machine do six?" needs numbers: how
many cores there are, how much memory is free, and roughly what one browser
window costs.

The per-browser figures are measured averages for a Chromium window on a
normal page — a heavy site costs more, an idle one less — so everything here
is an *estimate* and says so. What is not an estimate is the machine's own
cores and memory, and the load measured while a task actually runs.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

try:  # psutil gives real memory and load; the app still works without it.
    import psutil
except Exception:  # noqa: BLE001
    psutil = None  # type: ignore[assignment]

# One visible Chromium window: it renders, composites and animates.
CPU_PER_WINDOW = 0.55          # cores, while it is actually working
RAM_PER_WINDOW_MB = 380

# Headless does the same work minus painting, compositing and the window
# itself. Measured difference is roughly a third of the CPU and a fifth of
# the memory.
HEADLESS_CPU_FACTOR = 0.65
HEADLESS_RAM_FACTOR = 0.80

# The driver process and this backend also want a slice.
BASE_CPU = 0.25
BASE_RAM_MB = 220


@dataclass
class Machine:
    cores: int
    total_ram_mb: int
    available_ram_mb: int
    cpu_percent: float | None = None

    def to_dict(self) -> dict:
        return {
            "cores": self.cores,
            "total_ram_mb": self.total_ram_mb,
            "available_ram_mb": self.available_ram_mb,
            "cpu_percent": self.cpu_percent,
            "measured": psutil is not None,
        }


def machine() -> Machine:
    cores = os.cpu_count() or 2
    if psutil is not None:
        memory = psutil.virtual_memory()
        return Machine(
            cores=cores,
            total_ram_mb=int(memory.total / 1024 / 1024),
            available_ram_mb=int(memory.available / 1024 / 1024),
            cpu_percent=psutil.cpu_percent(interval=None),
        )
    # No psutil: report what os gives us and leave memory unknown (0).
    return Machine(cores=cores, total_ram_mb=0, available_ram_mb=0)


def estimate(windows: int, headless: bool = False) -> dict:
    """What `windows` browsers at once would cost on this machine."""
    windows = max(1, int(windows))
    info = machine()
    cpu_factor = HEADLESS_CPU_FACTOR if headless else 1.0
    ram_factor = HEADLESS_RAM_FACTOR if headless else 1.0

    cores_needed = BASE_CPU + windows * CPU_PER_WINDOW * cpu_factor
    ram_needed = int(BASE_RAM_MB + windows * RAM_PER_WINDOW_MB * ram_factor)
    load = cores_needed / info.cores if info.cores else 1.0

    if load <= 0.55:
        level = "easy"
    elif load <= 0.85:
        level = "busy"
    else:
        level = "over"

    # How many windows this machine can carry comfortably (~70% of cores),
    # and how many memory alone allows.
    by_cpu = max(
        1,
        int((info.cores * 0.7 - BASE_CPU) // (CPU_PER_WINDOW * cpu_factor)),
    )
    by_ram = windows
    if info.available_ram_mb:
        by_ram = max(
            1,
            int(
                (info.available_ram_mb - BASE_RAM_MB)
                // (RAM_PER_WINDOW_MB * ram_factor)
            ),
        )
    return {
        "windows": windows,
        "headless": headless,
        "cores_needed": round(cores_needed, 2),
        "ram_needed_mb": ram_needed,
        "load": round(load, 3),
        "level": level,
        "recommended": max(1, min(by_cpu, by_ram)),
        "machine": info.to_dict(),
    }


class LoadSampler:
    """Measures what a run really cost, so the estimate can be checked.

    Without psutil it simply reports nothing, and the caller carries on.
    """

    def __init__(self) -> None:
        self.peak_cpu: float | None = None
        self.peak_ram_mb: int | None = None
        self._process = psutil.Process() if psutil is not None else None

    def sample(self) -> None:
        if psutil is None:
            return
        try:
            cpu = psutil.cpu_percent(interval=None)
            used = psutil.virtual_memory().used / 1024 / 1024
        except Exception:  # noqa: BLE001
            return
        if self.peak_cpu is None or cpu > self.peak_cpu:
            self.peak_cpu = cpu
        if self.peak_ram_mb is None or used > self.peak_ram_mb:
            self.peak_ram_mb = int(used)

    def result(self) -> dict:
        return {"peak_cpu": self.peak_cpu, "peak_ram_mb": self.peak_ram_mb}
