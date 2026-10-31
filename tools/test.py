#!/usr/bin/env python3
"""Run Godot migration integration tests with isolated cache/config directories."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, env, log_dir, label, marker=None):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    log = log_dir / f"{label}.log"
    log.write_text(result.stdout)
    failed = result.returncode != 0 or "SCRIPT ERROR:" in result.stdout or "\nERROR:" in result.stdout
    if marker and marker not in result.stdout:
        failed = True
    if failed:
        print(result.stdout)
        raise SystemExit(f"{label} failed; log: {log}")
    print(f"{label}: passed ({log})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--render", action="store_true", help="Run gameplay with a display (use xvfb-run in CI)")
    parser.add_argument("--logs", type=Path, default=ROOT / ".artifacts" / "tests")
    args = parser.parse_args()
    godot = str(Path(args.godot).resolve()) if "/" in args.godot else args.godot
    args.logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="tabletop-godot4-") as temporary:
        env = dict(os.environ, XDG_DATA_HOME=temporary, XDG_CONFIG_HOME=temporary)
        command = [godot, "--headless", "--path", str(ROOT / "game")]
        run(command + ["--editor", "--import"], env, args.logs, "import")
        run(command + ["--script", "res://Tests/scripts.gd"], env, args.logs, "scripts", "SCRIPTS: all")
        run(command + ["--script", "res://Tests/multiplayer.gd"], env, args.logs, "multiplayer", "MULTIPLAYER:")
        gameplay = [godot, "--path", str(ROOT / "game"), "--audio-driver", "Dummy"]
        if not args.render:
            gameplay.append("--headless")
        run(gameplay + ["--script", "res://Tests/smoke.gd", "--", "--base-asset-dir", str(ROOT)],
            env, args.logs, "gameplay", "SMOKE: all checks passed")


if __name__ == "__main__":
    main()
