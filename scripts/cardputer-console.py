#!/usr/bin/env python3
"""Desktop test client for the exact JSONL protocol used by the Cardputer."""
import argparse
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", help="Without this option, run the local Rust binary.")
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--user", default="alice-card")
    parser.add_argument("--data-dir", type=Path, default=Path.home() / ".local/share/alice-cardputer")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.host:
        command = ["ssh", "-T", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
                   "-p", str(args.port), "-l", args.user, "--", args.host, "alice-card-v1"]
    else:
        command = [str(root / "target/release/alice-card-server"), "--data-dir", str(args.data_dir)]
    actions = {"f": "feed", "b": "bath", "s": "rest", "w": "wake", "h": "pet", "g": "start_game", "t": "tea"}
    print("f feed / b bath / s sleep / w wake / h pat / g pearl / t tea / r refresh")
    print("p1/p2/p3 personality; 1/2/3 guess; q quit. Commands require Enter.")
    # SSH prompts stay on the controlling terminal. Never disable host-key checks.
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
        sequence, request = 0, {"op": "snapshot"}
        try:
            while True:
                sequence += 1
                child.stdin.write(json.dumps({"v": 1, "id": sequence, **request}) + "\n")
                child.stdin.flush()
                line = child.stdout.readline(2048)
                if not line:
                    raise RuntimeError("Host closed the session. Check SSH/service logs.")
                response = json.loads(line)
                if response.get("id") != sequence or response.get("v") != 1:
                    raise RuntimeError("Unexpected protocol response.")
                print(response.get("message", ""))
                if "state" in response:
                    print(json.dumps(response["state"], ensure_ascii=False))
                while True:
                    key = input("alice> ").strip().lower()
                    if key == "q": return
                    if key in actions:
                        request = {"op": "action", "action": actions[key]}; break
                    if key in ("p1", "p2", "p3"):
                        request = {"op": "persona", "choice": int(key[1])}; break
                    if key in ("1", "2", "3"):
                        request = {"op": "action", "action": "guess", "guess": int(key) - 1}; break
                    if key == "r": request = {"op": "snapshot"}; break
                    print("Unknown key; use the commands above.")
        except (KeyboardInterrupt, EOFError):
            pass
        finally:
            child.stdin.close()
            try: child.wait(timeout=3)
            except subprocess.TimeoutExpired: child.terminate()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(str(error))
