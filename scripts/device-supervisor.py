#!/usr/bin/env python3
"""Start Alice in the logged-in graphical session; retry crashes, not clean exits."""
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

child = None
stopping = False


def stop(_signal, _frame):
    global stopping
    stopping = True
    if child is not None and child.poll() is None:
        child.terminate()


def main():
    global child
    if len(sys.argv) != 2:
        raise SystemExit("Usage: device-supervisor.py /path/to/bundle/alice_companion")
    binary = Path(sys.argv[1]).resolve(strict=True)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    environment = {**os.environ, "ALICE_DEVICE_MODE": "1"}
    failures = 0
    while not stopping and failures < 5:
        started = time.monotonic()
        child = subprocess.Popen([str(binary)], cwd=binary.parent, env=environment)
        try:
            result = child.wait()
        except KeyboardInterrupt:
            stop(None, None)
            result = child.wait(timeout=10)
        if stopping or result == 0:
            return
        failures = 1 if time.monotonic() - started > 300 else failures + 1
        # Bound retries; do not fill the SD card or spin on a broken installation.
        for _ in range(min(30, 2 ** failures)):
            if stopping:
                return
            time.sleep(1)
    if failures >= 5:
        raise SystemExit("Alice stopped after repeated startup failures. Check the bundle and system dependencies.")


if __name__ == "__main__":
    main()
