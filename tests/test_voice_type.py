import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


PATH = Path(__file__).resolve().parents[1] / "bin/voice-type.py"
SPEC = importlib.util.spec_from_file_location("voice_type", PATH)
voice = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(voice)


class VoiceBackendTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(voice.wave, "open")
        opened = patcher.start()
        self.addCleanup(patcher.stop)
        self.audio = opened.return_value.__enter__.return_value
        self.audio.getframerate.return_value = 16000
        self.audio.getnframes.return_value = 1600

    def test_auto_selects_parakeet_for_ac_and_battery(self):
        with mock.patch.object(voice, "selected_mode", return_value="auto"):
            with mock.patch.object(voice, "on_ac", return_value=True):
                self.assertEqual(voice.chosen_backend(), "parakeet-gpu")
            with mock.patch.object(voice, "on_ac", return_value=False):
                self.assertEqual(voice.chosen_backend(), "parakeet-cpu")

    def test_legacy_whisper_modes_stay_selectable(self):
        for mode in ("gpu", "npu", "parakeet-cpu", "parakeet-gpu"):
            with self.subTest(mode=mode), mock.patch.object(voice, "selected_mode", return_value=mode):
                self.assertEqual(voice.chosen_backend(), mode)

    def test_label_reports_parakeet_and_missing_install(self):
        with mock.patch.object(voice, "selected_mode", return_value="auto"), \
             mock.patch.object(voice, "chosen_backend", return_value="parakeet-gpu"), \
             mock.patch.object(voice, "parakeet_available", return_value=False), \
             mock.patch.object(voice, "on_ac", return_value=True):
            label = voice.backend_label()
        self.assertIn("Auto · Parakeet GPU", label["text"])
        self.assertIn("?", label["text"])
        self.assertIn("fallback", label["tooltip"])
        self.assertEqual(label["class"], "gpu")

    def test_selecting_whisper_npu_is_still_possible(self):
        with tempfile.TemporaryDirectory() as temp, \
             mock.patch.object(voice, "MODE_FILE", Path(temp) / "mode"), \
             mock.patch.object(voice.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="Whisper NPU\n")), \
             mock.patch.object(voice, "refresh_waybar"), mock.patch.object(voice, "notify"):
            voice.pick_backend()
            self.assertEqual(voice.MODE_FILE.read_text(), "npu\n")

    def test_cpu_command_uses_local_model_and_no_gpu(self):
        completed = subprocess.CompletedProcess([], 0, stdout="First line\nsecond line\n", stderr="")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.os, "cpu_count", return_value=24), \
             mock.patch.object(voice.subprocess, "run", return_value=completed) as run:
            self.assertEqual(voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-cpu"), "First line second line")
        command = run.call_args.args[0]
        self.assertEqual(command[0], str(voice.PARAKEET_CPU))
        self.assertIn("--no-gpu", command)
        self.assertIn("--no-prints", command)
        self.assertEqual(command[command.index("--threads") + 1], "12")
        self.assertEqual(command[-1], "/tmp/audio.wav")
        self.assertTrue(run.call_args.kwargs["env"]["LD_LIBRARY_PATH"].startswith(str(voice.PARAKEET_CPU.parent)))

    def test_empty_library_path_does_not_add_current_directory(self):
        completed = subprocess.CompletedProcess([], 0, stdout="hello", stderr="")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.dict(voice.os.environ, {"LD_LIBRARY_PATH": ""}), \
             mock.patch.object(voice.subprocess, "run", return_value=completed) as run:
            voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-cpu")
        self.assertEqual(run.call_args.kwargs["env"]["LD_LIBRARY_PATH"], str(voice.PARAKEET_CPU.parent))

    def test_gpu_backend_verification_and_completed_cpu_fallback(self):
        ok = subprocess.CompletedProcess([], 0, stdout="hello\n", stderr="parakeet_backend_init_gpu: using Vulkan0 backend\n")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.subprocess, "run", return_value=ok) as run:
            self.assertEqual(voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-gpu"), "hello")
        command = run.call_args.args[0]
        self.assertEqual(command[0], str(voice.PARAKEET_GPU))
        self.assertNotIn("--no-gpu", command)
        self.assertEqual(run.call_args.kwargs["env"]["VK_DRIVER_FILES"], str(voice.RADV_ICD))
        no_gpu = subprocess.CompletedProcess([], 0, stdout="hello", stderr="CPU fallback")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.subprocess, "run", return_value=no_gpu), \
             mock.patch.object(voice, "notify") as notify:
            self.assertEqual(voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-gpu"), "hello")
            notify.assert_called_once()

    def test_long_audio_uses_corresponding_whisper_backend(self):
        self.audio.getnframes.return_value = 16000 * (voice.PARAKEET_MAX_SECONDS + 1)
        with mock.patch.object(voice, "ensure_gpu") as ensure_gpu, \
             mock.patch.object(voice, "transcribe_gpu", return_value="whisper gpu"), \
             mock.patch.object(voice, "ensure_server") as ensure_npu, \
             mock.patch.object(voice, "transcribe", return_value="whisper npu"), \
             mock.patch.object(voice, "notify"), \
             mock.patch.object(voice.subprocess, "run") as run:
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-gpu"), "whisper gpu")
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-cpu"), "whisper npu")
            ensure_gpu.assert_called_once()
            ensure_npu.assert_called_once()
            run.assert_not_called()

    def test_audio_at_limit_can_use_parakeet(self):
        self.audio.getnframes.return_value = 16000 * voice.PARAKEET_MAX_SECONDS
        completed = subprocess.CompletedProcess([], 0, stdout="hello", stderr="")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.subprocess, "run", return_value=completed):
            self.assertEqual(voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-cpu"), "hello")

    def test_cli_error_is_failure_even_if_exit_status_is_zero(self):
        failed = subprocess.CompletedProcess([], 0, stdout="", stderr="error: failed to process audio file\n")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.subprocess, "run", return_value=failed):
            with self.assertRaises(RuntimeError):
                voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-cpu")

    def test_empty_success_is_not_an_error(self):
        empty = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice.subprocess, "run", return_value=empty):
            self.assertEqual(voice.transcribe_parakeet(Path("/tmp/audio.wav"), "parakeet-cpu"), "")

    def test_gpu_failure_retries_parakeet_cpu_before_whisper(self):
        with mock.patch.object(voice, "transcribe_parakeet", side_effect=[RuntimeError("bad GPU"), "cpu text"]) as parakeet, \
             mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice, "notify"), mock.patch.object(voice, "ensure_server") as npu:
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-gpu"), "cpu text")
        self.assertEqual([call.args[1] for call in parakeet.call_args_list], ["parakeet-gpu", "parakeet-cpu"])
        npu.assert_not_called()

    def test_parakeet_failure_falls_back_to_corresponding_whisper(self):
        with mock.patch.object(voice, "transcribe_parakeet", side_effect=RuntimeError("broken")), \
             mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice, "ensure_gpu") as ensure_gpu, \
             mock.patch.object(voice, "transcribe_gpu", return_value="whisper gpu"), \
             mock.patch.object(voice, "ensure_server") as ensure_npu, \
             mock.patch.object(voice, "transcribe", return_value="whisper npu"), \
             mock.patch.object(voice, "notify"):
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-gpu"), "whisper gpu")
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-cpu"), "whisper npu")
            ensure_gpu.assert_called_once()
            ensure_npu.assert_called_once()

    def test_all_gpu_and_parakeet_failures_fall_back_to_whisper_npu(self):
        with mock.patch.object(voice, "transcribe_parakeet", side_effect=RuntimeError("broken")), \
             mock.patch.object(voice, "parakeet_available", return_value=True), \
             mock.patch.object(voice, "ensure_gpu", side_effect=RuntimeError("broken")), \
             mock.patch.object(voice, "ensure_server") as ensure, \
             mock.patch.object(voice, "transcribe", return_value="whisper npu"), \
             mock.patch.object(voice, "notify"):
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-gpu"), "whisper npu")
            ensure.assert_called_once()

    def test_missing_cpu_skips_misleading_retry_notice(self):
        with mock.patch.object(voice, "transcribe_parakeet", side_effect=RuntimeError("missing")) as parakeet, \
             mock.patch.object(voice, "parakeet_available", return_value=False), \
             mock.patch.object(voice, "ensure_gpu"), \
             mock.patch.object(voice, "transcribe_gpu", return_value="whisper gpu"), \
             mock.patch.object(voice, "notify") as notify:
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "parakeet-gpu"), "whisper gpu")
        parakeet.assert_called_once()
        self.assertFalse(any("trying CPU" in call.args[0] for call in notify.call_args_list))

    def test_legacy_gpu_failure_still_falls_back_to_npu(self):
        with mock.patch.object(voice, "ensure_gpu", side_effect=RuntimeError("broken")), \
             mock.patch.object(voice, "ensure_server") as ensure, \
             mock.patch.object(voice, "transcribe", return_value="whisper text"), \
             mock.patch.object(voice, "notify"):
            self.assertEqual(voice.transcribe_with_fallback(Path("/tmp/audio.wav"), "gpu"), "whisper text")
            ensure.assert_called_once()


if __name__ == "__main__":
    unittest.main()
