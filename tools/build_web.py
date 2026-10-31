#!/usr/bin/env python3
"""Prebuild portable assets and export the single-threaded Matrix widget."""
import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
import shutil
import subprocess
import zipfile
ROOT = Path(__file__).resolve().parents[1]

def run_engine(command, **kwargs):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=600, **kwargs)
    print(result.stdout, end="", flush=True)
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "\nERROR:" in result.stdout:
        raise RuntimeError("Godot asset preparation/export failed")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--template", type=Path, help="Optional official web_nothreads_release.zip")
    args = parser.parse_args()
    output = ROOT / ".artifacts/web"
    output.mkdir(parents=True, exist_ok=True)
    run_engine([args.godot, "--headless", "--editor", "--path", str(ROOT / "game"), "--import"])
    archive = ROOT / "game/web_assets.zip"
    # Convex decomposition and runtime imports are done once at build time,
    # keeping the single-threaded browser startup fast and memory bounded.
    with tempfile.TemporaryDirectory(prefix="tabletop-web-assets-") as temporary:
        manifest = Path(temporary) / "manifest.json"
        run_engine([args.godot, "--headless", "--path", str(ROOT / "game"),
                        "--script", "res://Tools/BuildWebAssets.gd", "--",
                        "--base-asset-dir", str(ROOT), "--web-assets", "--output", str(manifest)],
                       env=dict(os.environ, XDG_DATA_HOME=temporary, XDG_CONFIG_HOME=temporary))
        cached = Path(json.loads(manifest.read_text())["user_directory"]) / "assets"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
            for prefix, directory in [("assets", ROOT / "assets"), ("cache/assets", cached)]:
                for path in sorted(directory.rglob("*")):
                    if not path.is_file(): continue
                    data = path.read_bytes()
                    if path.suffix == ".src":
                        data = data.decode().replace(str(ROOT), "user://bundled").encode()
                    info = zipfile.ZipInfo(prefix + "/" + str(path.relative_to(directory)))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    bundle.writestr(info, data)
    (ROOT / "game/web_assets.sha256").write_text(hashlib.sha256(archive.read_bytes()).hexdigest())
    command = [args.godot, "--headless", "--path", str(ROOT / "game")]
    run_engine(command + ["--editor", "--import"])
    preset = ROOT / "game/export_presets.cfg"
    original = preset.read_text()
    try:
        if args.template:
            preset.write_text(original.replace('custom_template/release=""', 'custom_template/release="' + args.template.resolve().as_posix() + '"'))
        run_engine(command + ["--export-release", "Web", str(output / "index.html")])
    finally:
        preset.write_text(original)
    subprocess.run(["npm", "run", "build:shell"], cwd=ROOT, check=True)
    shutil.copy(ROOT / "LICENSE", output / "LICENSE.txt")
    shutil.copy(ROOT / "node_modules/matrix-widget-api/LICENSE", output / "matrix-widget-api.LICENSE.txt")
    (output / ".nojekyll").touch()
    print(f"Web widget exported to {output}")

if __name__ == "__main__": main()
