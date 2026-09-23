#!/usr/bin/env python3
"""Keep whisper.cpp's GPU model resident until an idle timeout; local-only server."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import urllib.request

ROOT = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "voice-type"
INSTALL = Path.home() / ".local/share/voice-gpu"
BINARY = INSTALL / "bin/whisper-server"
MODEL = INSTALL / "models/ggml-large-v3-turbo.bin"
URL = "http://127.0.0.1:52629"
PORT = "52629"


def available():
    return BINARY.is_file() and MODEL.is_file()


def ready():
    try:
        with urllib.request.urlopen(URL + "/health", timeout=1) as response:
            return json.load(response).get("status") == "ok"
    except (OSError, ValueError):
        return False


def idle_seconds():
    try:
        minutes = int(os.environ.get("VOICE_GPU_IDLE_MINUTES", "10"))
    except ValueError:
        minutes = 10
    return min(60, max(1, minutes)) * 60


def main():
    stopping = False

    def request_stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(ROOT, 0o700)
    with open(ROOT / "gpu.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if not available():
            raise RuntimeError("GPU whisper server or model missing from ~/.local/share/voice-gpu")
        # Use the Mesa ICD verified against this build's Nix Vulkan loader.
        preferred = Path("/nix/store/1vkzwrp4ny20iljfnv9valq0bfn8czlv-mesa-26.2.3/share/vulkan/icd.d/radeon_icd.x86_64.json")
        if not preferred.is_file():
            raise RuntimeError("The verified RADV ICD is missing; GPU backend disabled")
        env = dict(os.environ, VK_DRIVER_FILES=str(preferred), GGML_VK_VISIBLE_DEVICES="0")
        last_use = ROOT / "gpu-last-use"
        last_use.touch(exist_ok=True)
        os.utime(last_use, None)
        with open(ROOT / "gpu-server.log", "ab", buffering=0) as log:
            server = subprocess.Popen([str(BINARY), "--model", str(MODEL), "--host", "127.0.0.1",
                                       "--port", PORT, "--threads", "6"], env=env,
                                      stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
            try:
                while not stopping and server.poll() is None:
                    try:
                        last = (ROOT / "gpu-last-use").stat().st_mtime
                    except OSError:
                        last = time.time()
                    if time.time() - last > idle_seconds():
                        break
                    time.sleep(2)
            finally:
                if server.poll() is None:
                    server.terminate()
                    try:
                        server.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        server.kill()
                        server.wait()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"voice-gpu-server: {exc}", file=sys.stderr)
        sys.exit(1)
