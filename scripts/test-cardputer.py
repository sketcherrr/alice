#!/usr/bin/env python3
"""Real-process/reconnect checks; no device, network listener or OpenAI key required."""
import importlib.util
import json
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target/release/alice-card-server"
spec = importlib.util.spec_from_file_location("provision", ROOT / "scripts/configure-cardputer.py")
provision = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provision)


class CardTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="alice-card-test-")
        self.path = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def run_session(self, requests):
        wire = "".join(json.dumps({"v": 1, "id": i, **request}) + "\n" for i, request in enumerate(requests))
        result = subprocess.run([str(BINARY), "--data-dir", str(self.path)], input=wire,
                                capture_output=True, text=True, timeout=10, check=True)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_process_exit_reconnect_restores_same_pet(self):
        first = self.run_session([{"op": "persona", "choice": 3}, {"op": "action", "action": "feed"},
                                  {"op": "action", "action": "bath"}, {"op": "action", "action": "rest"}])
        self.assertTrue(all(reply["ok"] for reply in first))
        restored = self.run_session([{"op": "snapshot"}])[0]["state"]
        self.assertEqual(restored["persona"], "reserved_attentive")
        self.assertTrue(restored["sleeping"])
        self.assertEqual(restored["satiety"], 95)
        self.assertEqual(restored["cleanliness"], 100)
        with sqlite3.connect(self.path / "companion.sqlite3") as connection:
            saved = json.loads(connection.execute("SELECT data FROM companion WHERE id=1").fetchone()[0])
        self.assertGreater(len(saved["events"]), 2)
        self.assertEqual(saved["version"], 2)

    def test_rejected_operation_cannot_edit_memory(self):
        self.run_session([{"op": "persona", "choice": 1}])
        rejected, state = self.run_session([{"op": "remember", "content": "not authorized"}, {"op": "snapshot"}])
        self.assertEqual(rejected["code"], "bad_operation")
        self.assertNotIn("memories", state["state"])
        with sqlite3.connect(self.path / "companion.sqlite3") as connection:
            saved = json.loads(connection.execute("SELECT data FROM companion WHERE id=1").fetchone()[0])
        self.assertEqual(saved["memories"], [])

    def test_forced_command_environment_is_not_executed(self):
        marker = self.path / "should-not-exist"
        result = subprocess.run([str(BINARY), "--data-dir", str(self.path)], input='{"v":1,"id":0,"op":"snapshot"}\n',
                                capture_output=True, text=True, timeout=10, check=True,
                                env={**os.environ, "SSH_ORIGINAL_COMMAND": f"touch {marker}"})
        self.assertTrue(json.loads(result.stdout)["ok"])
        self.assertFalse(marker.exists())

    def test_torn_write_does_not_create_persona(self):
        subprocess.run([str(BINARY), "--data-dir", str(self.path)],
                       input='{"v":1,"id":1,"op":"persona","choice":1}', text=True,
                       capture_output=True, timeout=10, check=True)
        self.assertIsNone(self.run_session([{"op": "snapshot"}])[0]["state"]["persona"])

    def config_file(self, **changes):
        data = {"wifi_ssid": "Test", "wifi_password": "test-password", "ssh_host": "192.168.1.10",
                "ssh_port": 2222, "ssh_user": "alice-card", "ssh_password": "dedicated-password",
                "host_fingerprint": "SHA256:" + "a" * 43, **changes}
        file = self.path / "config.json"
        file.write_text(json.dumps(data), encoding="utf-8")
        return file

    def test_provisioning_rejects_placeholder_pin_and_invalid_config(self):
        for changes in [{"host_fingerprint": ""}, {"host_fingerprint": "SHA256:REPLACE_ME"},
                        {"ssh_port": True}, {"ssh_port": 0}, {"ssh_host": "bad\nvalue"},
                        {"wifi_ssid": "鲸" * 11}, {"ssh_password": ""}]:
            with self.assertRaises(ValueError):
                provision.load_config(self.config_file(**changes))
        wire = provision.load_config(self.config_file(wifi_ssid="鲸屿", wifi_password=""))
        self.assertEqual(json.loads(wire)["wifi_ssid"], "鲸屿")
        self.assertEqual(wire.count(b"\n"), 1)


if __name__ == "__main__":
    unittest.main()
