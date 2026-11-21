#!/usr/bin/env python3
"""Keep the local speculative cleanup model warm while dictation is in use."""

import fcntl
import http.client
import json
import os
from pathlib import Path
import resource
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "voice-type"
SOCKET = ROOT / "fast-editor.sock"
LAST_USE = ROOT / "fast-editor-last-use"
INSTALL = Path.home() / ".local/share/voice-fast-editor"
BINARY = INSTALL / "bin/llama-server"
MODEL = INSTALL / "models/qwen3-4b-instruct-2507-q4_k_m.gguf"
SYSTEM_RADV_ICD = Path("/usr/share/vulkan/icd.d/radeon_icd.x86_64.json")
IDLE_SECONDS = 120


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout):
        super().__init__("localhost", timeout=timeout)
        self.path = str(path)

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.settimeout(self.timeout)
            sock.connect(self.path)
        except BaseException:
            sock.close()
            raise
        self.sock = sock


def ready():
    connection = UnixHTTPConnection(SOCKET, timeout=0.2)
    try:
        connection.request("GET", "/health")
        response = connection.getresponse()
        response.read()
        return response.status == 200
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


def recording_active():
    try:
        state = json.loads((ROOT / "recording.json").read_text())
        pid = int(state["pid"])
        args = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        return args[0].endswith(b"pw-record") and os.fsencode(ROOT / "recording.wav") in args
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        return False


def main():
    stopping = False

    def request_stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(ROOT, 0o700)
    with open(ROOT / "fast-editor.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if ready():
            return
        if not BINARY.is_file() or not MODEL.is_file() or not SYSTEM_RADV_ICD.is_file():
            raise RuntimeError("Fast editor runtime, model or system RADV driver is missing")
        SOCKET.unlink(missing_ok=True)
        LAST_USE.touch(exist_ok=True)
        env = dict(os.environ, LD_LIBRARY_PATH=str(BINARY.parent), GGML_VK_VISIBLE_DEVICES="0",
                   VK_DRIVER_FILES=str(SYSTEM_RADV_ICD))
        env.pop("GGML_BACKEND_PATH", None)
        env.pop("VK_ICD_FILENAMES", None)
        # The model sees dictated text in memory; never emit core dumps or server logs.
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        server = subprocess.Popen([
            str(BINARY), "--model", str(MODEL), "--alias", "voice-editor",
            "--host", str(SOCKET), "--ctx-size", "4096", "--parallel", "1",
            "--threads", "6", "--device", "Vulkan0", "--n-gpu-layers", "all",
            "--no-webui", "--no-slots", "--log-disable", "--jinja",
            "--spec-type", "ngram-simple", "--spec-ngram-simple-size-n", "4",
            "--spec-ngram-simple-size-m", "48",
        ], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, umask=0o077)
        last_activity = time.monotonic()
        last_mtime = LAST_USE.stat().st_mtime_ns
        try:
            while not stopping and server.poll() is None:
                try:
                    mtime = LAST_USE.stat().st_mtime_ns
                    if mtime != last_mtime:
                        last_activity = time.monotonic()
                        last_mtime = mtime
                except OSError:
                    pass
                if recording_active():
                    last_activity = time.monotonic()
                if time.monotonic() - last_activity >= IDLE_SECONDS:
                    break
                time.sleep(1)
        finally:
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
            SOCKET.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"voice-fast-editor-server: {type(exc).__name__}", file=sys.stderr)
        sys.exit(1)
