#!/usr/bin/env python3
"""Run two rendered game instances against an isolated upstream TLS lobby.

Requires node, npm, openssl, and a display (xvfb-run works on Linux).
The server, its dependencies, certificates, and user directories are temporary.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REVISION = "4c80f835c613d7657bdbce17eb9d1082f9294b6b"
SERVER_SHA256 = "426f8291402a22a941b82d6e5f113b7f4f78e6374cb15361d7a282aad57880d0"


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    executable = str(Path(args.godot).resolve()) if "/" in args.godot else args.godot
    logs = ROOT / ".artifacts" / "tests"
    logs.mkdir(parents=True, exist_ok=True)
    url = f"https://raw.githubusercontent.com/drwhut/tabletop_club_master_server/{REVISION}/server.js"
    with urllib.request.urlopen(url, timeout=60) as response:
        source = response.read()
    if hashlib.sha256(source).hexdigest() != SERVER_SHA256:
        raise SystemExit("Upstream test server checksum mismatch")
    with tempfile.TemporaryDirectory(prefix="tabletop-session-") as temporary:
        temporary = Path(temporary)
        lobby_port, metrics_port = free_port(), free_port()
        (temporary / "server.js").write_text(source.decode().replace(
            "const WS_PORT = 9080;", f"const WS_PORT = {lobby_port};").replace(
            "const PROM_PORT = 9110;", f"const PROM_PORT = {metrics_port};"))
        # Match the upstream ws 7 protocol API: ws 8 delivers text as Buffers.
        (temporary / "package.json").write_text(json.dumps({"private": True, "dependencies": {
            "ws": "7.5.10", "express": "4.21.2", "prom-client": "14.2.0"}}))
        with (logs / "session-setup.log").open("w") as setup_log:
            subprocess.run(["npm", "install", "--ignore-scripts", "--no-audit", "--no-fund"],
                           cwd=temporary, stdout=setup_log, stderr=subprocess.STDOUT, check=True, timeout=120)
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "private.pem",
                            "-out", "public.crt", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                            "-days", "1"], cwd=temporary, stdout=setup_log, stderr=subprocess.STDOUT, check=True)
        custom = temporary / "host-assets"
        extra = custom / "assets/MigrationTest/tokens/cube"
        extra.mkdir(parents=True)
        (custom / "assets/TabletopClub").symlink_to(ROOT / "assets/TabletopClub", target_is_directory=True)
        shutil.copy(ROOT / "game/Images/BlackTexture.png", extra / "Test.png")
        children, handles = [], []
        try:
            handle = (logs / "session-server.log").open("w")
            handles.append(handle)
            children.append(subprocess.Popen(["node", "server.js"], cwd=temporary, stdout=handle, stderr=subprocess.STDOUT))
            for attempt in range(100):
                try:
                    with socket.create_connection(("127.0.0.1", lobby_port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.05)
            for role in ["host", "client"]:
                handle = (logs / f"session-{role}.log").open("w")
                handles.append(handle)
                data = temporary / role
                data.mkdir()
                command = [executable, "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                           "--script", "res://Tests/session.gd", "--", "--base-asset-dir",
                           str(custom if role == "host" else ROOT), "--master-server", f"wss://localhost:{lobby_port}",
                           "--ssl-certificate", str(temporary / "public.crt"), "--session-file", str(temporary / "room"),
                           "--session-transfer"]
                if role == "host":
                    command.append("--session-host")
                children.append(subprocess.Popen(command, env=dict(os.environ, XDG_DATA_HOME=str(data), XDG_CONFIG_HOME=str(data)),
                                                 stdout=handle, stderr=subprocess.STDOUT))
            for role, process in zip(["host", "client"], children[1:]):
                code = process.wait(timeout=180)
                output = (logs / f"session-{role}.log").read_text()
                if code != 0 or f"SESSION: {role} passed" not in output or "SCRIPT ERROR:" in output or "\nERROR:" in output:
                    raise SystemExit(f"Session {role} failed (exit {code}); see {logs / f'session-{role}.log'}")
            print("SESSION: TLS signaling, host/client sync, missing asset transfer/import, and gameplay passed")
        finally:
            for process in children:
                if process.poll() is None:
                    process.terminate()
            for process in children:
                process.wait(timeout=10)
            for handle in handles:
                handle.close()


if __name__ == "__main__":
    main()
