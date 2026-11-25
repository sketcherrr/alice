#!/usr/bin/env python3
"""Provision over USB serial. Never print configuration values or device echoes."""
import argparse
import json
import re
import time
from pathlib import Path


def load_config(path):
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    fields = {"wifi_ssid", "wifi_password", "ssh_host", "ssh_port", "ssh_user", "ssh_password", "host_fingerprint"}
    if not isinstance(document, dict) or set(document) != fields:
        raise ValueError("Use exactly the fields from alice.example.json.")
    for key in fields - {"ssh_port"}:
        value = document[key]
        if not isinstance(value, str) or len(value.encode()) > 128 or any(ord(c) < 32 for c in value):
            raise ValueError(f"Invalid field: {key}")
    if not 1 <= len(document["wifi_ssid"].encode()) <= 32:
        raise ValueError("SSID must be 1–32 bytes.")
    if not all(document[key] for key in ("ssh_host", "ssh_user", "ssh_password")):
        raise ValueError("Host, user and SSH password are required.")
    if type(document["ssh_port"]) is not int or not 1 <= document["ssh_port"] <= 65535:
        raise ValueError("Invalid SSH port.")
    if not re.fullmatch(r"SHA256:[A-Za-z0-9+/]{43}", document["host_fingerprint"]):
        raise ValueError("Copy the full SHA256:... fingerprint from the host installer.")
    wire = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
    if len(wire) > 1536:
        raise ValueError("Configuration exceeds device capacity.")
    return wire + b"\n"


def provision(port, wire):
    import serial
    # Set control lines before open; opening a USB port must not request flash mode.
    with serial.Serial(port=None, baudrate=115200, timeout=0.2, write_timeout=3) as device:
        device.dtr = False
        device.rts = False
        device.port = port
        device.open()
        deadline = time.monotonic() + 20
        next_probe = 0
        while time.monotonic() < deadline:
            if time.monotonic() >= next_probe:
                device.write(b"ALICE_SETUP\n")
                next_probe = time.monotonic() + 1
            if device.readline(256).strip() == b"ALICE_READY":
                break
        else:
            raise RuntimeError("No setup response. Hold G0 for 1.5 seconds, then retry; close serial monitors.")
        device.write(wire)
        device.flush()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            reply = device.readline(256).strip()
            if reply == b"ALICE_SAVED":
                return
            if reply in (b"ALICE_INVALID", b"ALICE_SAVE_FAILED"):
                raise RuntimeError("Device rejected configuration or could not save it.")
        raise RuntimeError("Save confirmation missing. Check the device screen before retrying.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="e.g. /dev/ttyACM0")
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    try:
        wire = load_config(args.config)
        provision(args.port, wire)
    except ImportError:
        parser.exit(1, "pyserial missing; run using the PlatformIO Python environment.\n")
    except (ValueError, OSError, RuntimeError) as error:
        # JSONDecodeError includes syntax, never the supplied document.
        parser.exit(1, f"Setup failed: {error}\n")
    print("Configuration saved; device is restarting. No credentials were printed.")


if __name__ == "__main__":
    main()
