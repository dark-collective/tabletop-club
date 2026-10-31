#!/usr/bin/env python3
"""Install the pinned official WebRTC GDExtension for desktop builds."""
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

VERSION = "1.2.2-stable"
SHA256 = "98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5"
URL = f"https://github.com/godotengine/webrtc-native/releases/download/{VERSION}/godot-extension-webrtc_native.zip"

if __name__ == "__main__":
    request = urllib.request.Request(URL, headers={"User-Agent": "Tabletop-Club-setup"})
    with urllib.request.urlopen(request, timeout=120) as response:
        archive = response.read()
    if hashlib.sha256(archive).hexdigest() != SHA256:
        raise SystemExit("WebRTC archive checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(archive)) as source:
        source.extractall(Path(__file__).resolve().parents[1] / "game")
    print(f"Installed official webrtc-native {VERSION}")
