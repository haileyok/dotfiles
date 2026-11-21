# Local fast transcript editor

The fast editor runs Qwen3-4B-Instruct-2507 on the Radeon GPU with speculative
decoding. The current transcript is proposed as a draft; the target model
verifies draft tokens before accepting them. Speculative and ordinary greedy
inference may still differ around numerical ties, and Q4_K_M is not the same
quantization as the NPU model, so outputs are not guaranteed to be identical.

`bin/voice-fast-editor-server.py` serves the model only on a private Unix socket
under the 0700 `voice-type` runtime directory, with the web UI, slots endpoint,
server logging, and core dumps disabled. It starts while recording and unloads
after two idle minutes. A failed GPU editor falls back to the existing NPU
editor. The caller waits for a completed response rather than dropping edits at
one second. The existing 180-word cleanup limit still applies.

This is a local install, not provisioned by `setup.sh` or the Nix profile:

- Binary and shared libraries: `~/.local/share/voice-fast-editor/bin/`
- Model: `~/.local/share/voice-fast-editor/models/qwen3-4b-instruct-2507-q4_k_m.gguf`
- Model source: [Qwen3-4B-Instruct-2507 GGUF](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF), Apache-2.0.
- Model SHA-256: `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`.
- Server source: llama.cpp tag `b12048`, commit `2c93f0b6e1f8417d898e21a729ba324032ed16d4`.
- `llama-draft-text.patch` is based on [WhisperNow's draft-text patch](https://github.com/stephan271c/WhisperNow/blob/b20cf67217513e4abdba0fd2629c681f85ed0a44/training/serving/llama-server-draft-text.patch),
  MIT licensed; `WHISPERNOW-LICENSE` preserves its notice. The local patch
  expands the candidate window from 24 to 64 words for this GPU.

To rebuild on another machine, check out the pinned llama.cpp commit and apply
`git apply --unidiff-zero ~/dotfiles/voice/fast-editor/llama-draft-text.patch`.
The patch has no context lines, so apply it only to that exact commit. Build
`llama-server` with `GGML_VULKAN=ON`, `GGML_NATIVE=ON`, `LLAMA_CURL=OFF`, and
`LLAMA_USE_PREBUILT_UI=OFF`. The build
requires CMake, a C++ compiler, Vulkan and SPIR-V headers, and `glslc`. Copy the
resulting server and its shared libraries into the install `bin/` directory.
The worker uses the **system** Vulkan loader and RADV ICD; do not assume a
Nix-built Mesa is ABI-compatible with it.

To use the previous NPU editor instead:

```sh
mkdir -p ~/.config/voice-type
printf 'npu\n' > ~/.config/voice-type/editor-mode
```

To return to the fast editor, write `fast` to the same file or remove it.
