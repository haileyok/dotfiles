import fcntl
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
from unittest import mock


PATH = Path(__file__).resolve().parents[1] / "bin/voice-type.py"
SPEC = importlib.util.spec_from_file_location("fast_voice_type", PATH)
voice = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(voice)


class FastCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.mode = mock.patch.object(voice, "editor_mode", return_value="fast")
        self.use = mock.patch.object(voice, "FAST_EDITOR_LAST_USE", self.root / "last-use")
        self.ready = mock.patch.object(voice, "ensure_fast_editor", return_value=True)
        self.mode.start()
        self.use.start()
        self.ready.start()
        self.addCleanup(self.mode.stop)
        self.addCleanup(self.use.stop)
        self.addCleanup(self.ready.stop)

    def choice(self, text, finish="stop"):
        return {"message": {"content": text}, "finish_reason": finish}

    def test_safe_grammar_edit_is_retained(self):
        raw = "we was planning to meet on tuesday"
        with mock.patch.object(voice, "fast_editor_request", return_value=self.choice("We were planning to meet on Tuesday.")):
            self.assertEqual(voice.cleanup_transcript(raw), "We were planning to meet on Tuesday.")

    def test_numeric_mutation_is_rejected(self):
        cases = [
            ("that is zero point zero one not zero point one", "that is zero point one not zero point one"),
            ("the threshold is 0.01 not 0.1", "the threshold is 0.1 not 0.1"),
            ("set it to fifteen not fifty", "set it to fifteen not fifteen"),
        ]
        for raw, edited in cases:
            with self.subTest(raw=raw), mock.patch.object(voice, "fast_editor_request", return_value=self.choice(edited)):
                self.assertEqual(voice.cleanup_transcript(raw), raw)

    def test_incomplete_thought_is_not_completed(self):
        raw = "if we deploy the service before"
        with mock.patch.object(voice, "fast_editor_request", return_value=self.choice("if we deploy the service first")):
            self.assertEqual(voice.cleanup_transcript(raw), raw)

    def test_large_contiguous_deletion_is_rejected(self):
        raw = "we need to review the proposed database migration carefully before the deploy"
        edited = "we need to review carefully before the deploy"
        with mock.patch.object(voice, "fast_editor_request", return_value=self.choice(edited)):
            self.assertEqual(voice.cleanup_transcript(raw), raw)

    def test_timeout_waits_for_npu_editor(self):
        report = []
        with mock.patch.object(voice, "fast_editor_request", side_effect=TimeoutError), \
             mock.patch.object(voice, "npu_editor_request", return_value=self.choice("Please leave this unchanged.")) as npu:
            raw = "please leave this unchanged"
            self.assertEqual(voice.cleanup_transcript(raw, report=report), "Please leave this unchanged.")
            npu.assert_called_once()
        self.assertIn("NPU", report[0])

    def test_both_editors_unavailable_keeps_raw(self):
        report = []
        with mock.patch.object(voice, "fast_editor_request", side_effect=FileNotFoundError), \
             mock.patch.object(voice, "npu_editor_request", side_effect=RuntimeError):
            raw = "please keep the original"
            self.assertEqual(voice.cleanup_transcript(raw, report=report), raw)
        self.assertIn("original transcript", report[0])

    def test_malformed_fast_response_uses_npu(self):
        report = []
        with mock.patch.object(voice, "fast_editor_request", return_value={"message": {"content": 123}, "finish_reason": "stop"}), \
             mock.patch.object(voice, "npu_editor_request", return_value=self.choice("Please keep it.")):
            self.assertEqual(voice.cleanup_transcript("please keep it", report=report), "Please keep it.")
        self.assertIn("NPU", report[0])

    def test_malformed_npu_response_keeps_original(self):
        raw = "please keep it"
        report = []
        with mock.patch.object(voice, "fast_editor_request", side_effect=RuntimeError), \
             mock.patch.object(voice, "npu_editor_request", return_value={"message": {"content": 123}, "finish_reason": "stop"}):
            self.assertEqual(voice.cleanup_transcript(raw, report=report), raw)
        self.assertIn("original transcript", report[0])

    def test_incomplete_response_uses_npu_not_partial_text(self):
        raw = "the entire original message"
        report = []
        with mock.patch.object(voice, "fast_editor_request", return_value=self.choice("the entire", finish="length")), \
             mock.patch.object(voice, "npu_editor_request", return_value=self.choice("The entire original message.")):
            self.assertEqual(voice.cleanup_transcript(raw, report=report), "The entire original message.")
        self.assertIn("NPU", report[0])

    def test_long_transcripts_are_left_unchanged(self):
        raw = "word " * 181
        with mock.patch.object(voice, "fast_editor_request") as request:
            self.assertEqual(voice.cleanup_transcript(raw), raw)
            request.assert_not_called()


class FastStartupTests(unittest.TestCase):
    def test_recording_prewarm_runs_only_for_fast_mode(self):
        for mode in ("fast", "npu"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp, \
                 mock.patch.object(voice, "ROOT", Path(temp)), \
                 mock.patch.object(voice, "editor_mode", return_value=mode), \
                 mock.patch.object(voice, "chosen_backend", return_value="parakeet-cpu"), \
                 mock.patch.object(voice, "mic_target", return_value="test-mic"), \
                 mock.patch.object(voice, "set_status"), mock.patch.object(voice, "notify"), \
                 mock.patch.object(voice, "start_fast_editor") as start, \
                 mock.patch.object(voice.subprocess, "run"), \
                 mock.patch.object(voice.subprocess, "Popen", return_value=mock.Mock(pid=123)):
                voice.start()
                if mode == "fast":
                    start.assert_called_once()
                else:
                    start.assert_not_called()

    def test_fast_is_default_and_npu_can_be_selected(self):
        with tempfile.TemporaryDirectory() as temp, \
             mock.patch.object(voice, "EDITOR_MODE_FILE", Path(temp) / "editor-mode"):
            self.assertEqual(voice.editor_mode(), "fast")
            voice.EDITOR_MODE_FILE.write_text("npu\n")
            self.assertEqual(voice.editor_mode(), "npu")
            voice.EDITOR_MODE_FILE.write_text("unknown\n")
            self.assertEqual(voice.editor_mode(), "fast")

    def test_missing_server_starts_worker_and_waits_for_readiness(self):
        with mock.patch.object(voice, "fast_editor_ready", side_effect=[False, True]), \
             mock.patch.object(voice, "fast_editor_available", return_value=True), \
             mock.patch.object(voice, "start_fast_editor") as start:
            self.assertTrue(voice.ensure_fast_editor(time.monotonic() + 1))
            start.assert_called_once()

    def test_missing_install_falls_back_without_waiting_or_spawning(self):
        with mock.patch.object(voice, "fast_editor_ready", return_value=False), \
             mock.patch.object(voice, "fast_editor_available", return_value=False), \
             mock.patch.object(voice, "start_fast_editor") as start:
            self.assertFalse(voice.ensure_fast_editor(time.monotonic() + 1))
            start.assert_not_called()


class UnixStreamingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "editor.sock"
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(str(self.path))
        self.listener.listen(1)
        self.addCleanup(self.listener.close)

    def serve(self, chunks, delay=0):
        ready = threading.Event()

        def run():
            ready.set()
            try:
                conn, _ = self.listener.accept()
                with conn:
                    conn.recv(65536)
                    if delay:
                        time.sleep(delay)
                    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
                    for chunk in chunks:
                        conn.sendall(chunk)
            except OSError:
                pass

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        ready.wait(1)
        self.addCleanup(lambda: thread.join(timeout=1))

    def test_streamed_content_and_stop_are_reassembled(self):
        events = [
            {"choices": [{"delta": {"content": "Hello"}, "finish_reason": None}]},
            {"choices": [{"delta": {"content": " world."}, "finish_reason": None}]},
            {"choices": [{"delta": {}, "finish_reason": "stop"}]},
        ]
        self.serve([b"data: " + json.dumps(e).encode() + b"\n\n" for e in events])
        with mock.patch.object(voice, "FAST_EDITOR_SOCKET", self.path):
            result = voice.fast_editor_request({"stream": True}, time.monotonic() + 1)
        self.assertEqual(result, {"message": {"content": "Hello world."}, "finish_reason": "stop"})

    def test_stream_without_finish_is_rejected(self):
        self.serve([b'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n', b"data: [DONE]\n\n"])
        with mock.patch.object(voice, "FAST_EDITOR_SOCKET", self.path):
            with self.assertRaises(ValueError):
                voice.fast_editor_request({"stream": True}, time.monotonic() + 1)

    def test_malformed_event_is_rejected(self):
        self.serve([b'data: {"choices":[{"delta":[],"finish_reason":"stop"}]}\n\n'])
        with mock.patch.object(voice, "FAST_EDITOR_SOCKET", self.path):
            with self.assertRaises(ValueError):
                voice.fast_editor_request({"stream": True}, time.monotonic() + 1)

    def test_unresponsive_server_respects_absolute_deadline(self):
        self.serve([], delay=0.3)
        with mock.patch.object(voice, "FAST_EDITOR_SOCKET", self.path):
            start = time.monotonic()
            with self.assertRaises(TimeoutError):
                voice.fast_editor_request({"stream": True}, start + 0.05)
            self.assertLess(time.monotonic() - start, 0.2)


class FastWorkerTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[1] / "bin/voice-fast-editor-server.py"
        spec = importlib.util.spec_from_file_location("fast_voice_worker", path)
        self.worker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.worker)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.worker.ROOT = root
        self.worker.SOCKET = root / "fast-editor.sock"
        self.worker.LAST_USE = root / "fast-editor-last-use"
        self.worker.BINARY = root / "bin/llama-server"
        self.worker.MODEL = root / "models/model.gguf"
        self.worker.SYSTEM_RADV_ICD = root / "radeon.json"
        self.worker.BINARY.parent.mkdir()
        self.worker.MODEL.parent.mkdir()
        for path in (self.worker.BINARY, self.worker.MODEL, self.worker.SYSTEM_RADV_ICD):
            path.touch()

    def test_worker_uses_private_socket_and_suppresses_model_logs(self):
        server = mock.Mock()
        server.poll.side_effect = [None, 0, 0]
        with mock.patch.object(self.worker, "ready", return_value=False), \
             mock.patch.object(self.worker, "recording_active", return_value=False), \
             mock.patch.object(self.worker.signal, "signal"), \
             mock.patch.object(self.worker.resource, "setrlimit"), \
             mock.patch.object(self.worker.time, "sleep"), \
             mock.patch.object(self.worker.subprocess, "Popen", return_value=server) as popen:
            self.worker.main()
        command = popen.call_args.args[0]
        self.assertEqual(command[command.index("--host") + 1], str(self.worker.SOCKET))
        self.assertIn("--no-slots", command)
        self.assertIn("--no-webui", command)
        self.assertIn("--log-disable", command)
        self.assertEqual(popen.call_args.kwargs["umask"], 0o077)
        self.assertEqual(popen.call_args.kwargs["stdout"], self.worker.subprocess.DEVNULL)
        self.assertEqual(popen.call_args.kwargs["stderr"], self.worker.subprocess.DEVNULL)

    def test_second_worker_does_not_replace_running_server(self):
        with open(self.worker.ROOT / "fast-editor.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with mock.patch.object(self.worker.signal, "signal"), \
                 mock.patch.object(self.worker.subprocess, "Popen") as popen:
                self.worker.main()
                popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
