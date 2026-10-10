# Goal 001 progress notes — AirPods on Linux like a Mac

Vehicle: MagicPods fork at ~/personal/magicpods-fork (submodule rev d799715 = the nix-pinned rev).
Reference implementation: ~/personal/librepods-hires (LuanAdemi/librepods PR #655 branch, linux/rust).

## Layer status

| Layer | Status | Where |
|---|---|---|
| Control plane (AACP) | ✅ working | PR #655 app live (service `hires-mic-live`) + stock MagicPods |
| Hi-res voice codec (AAC-ELD 64k over AACP 0x58) | ✅ RE'd + live-verified (2548 frames, 0 errors; spectrum shows 24.6% energy 8–16kHz) | PR #655 app; port to fork in progress |
| Pairing popup data layer | ✅ decoded (live: L62/R73/Case71-charging via ENC_KEY) | adv-decode prototype + stock MagicPods `AppAnimationCapability` |
| Pairing popup rendering | ✅ chain exists upstream (DBusBasedBleAdvertisingService → ParseBle → PopupAnimation.qml); live test pending user's case-lid | stock magicpods |
| Handoff (Smart Routing) | ✅ PORTED into MagicPodsCore (branch hailey/handoff, commit 29bd9fa): 5 exact-byte setters + AapHandoffCapability (0x2E/0x0E/0x11 parsing — LIVE-VERIFIED: buds reported this laptop + another host 80:96:98:54:E7:93), feature-flags/notifications startup packets enabling 0x2E emission, hijack/release via SetCapabilities. Actions NOT yet live-tested (need other host actively using buds + {"handoff":{"enabled":true}}). Protocol gotchas: 0x2E device MACs NOT reversed; 0x0E source MAC IS reversed; HijackReversed reason=0x53 "ReverseBannerTapped"; ShowUI "reasonHhijackv2" double-H is literal | memory 3mxkcnoiv2q22; Kotlin AACPManager.kt |
| Head tracking | 📄 transport mapped (opcode 0x17: start 22B TLV `0x7E 0x02 0x42…`, alt-start, stop `0x7E 0x10 0x02 0x42 0x0B 0x08 0x4E…`, inbound frames ≥70B) — but NOBODY has decoded the orientation payload (Android forwards raw frames, no parsing). Transportable, not yet useful. Future frontier. | Android AACPManager.kt 495-730 |

## Head tracking capture attempts (2026-10-10, continuation 12) — KEY FINDING
- Built ~/personal/headtracking-capture/capture.py (Python raw L2CAP SOCK_SEQPACKET PSM 0x1001): handshake + feature flags + notifications all WORK live (buds responded with 0x53 EQ-data); head-tracking START (0x17, exact Kotlin bytes) sent — ZERO 0x17 frames came back (both attempts).
- ROOT CAUSE (Android AirPodsService.kt:2767-2787): startHeadTracking() first checks ControlCommand OWNS_CONNECTION (identifier 0x06) == 1; if NOT, it calls takeOver("call", startHeadTrackingAgain=true) — a Smart-Routing-style takeover — BEFORE sending 0x17. **Head tracking requires the host to own the connection first.** That's why the buds ignored our 0x17.
- takeOver (AirPodsService.kt:2196+): if audio source != self or not owns_connection → hijack sequence; for "reverse" it sends control command OWNS_CONNECTION=1 + sendMediaInformataion + sendHijackReversed.
- Control commands: opcode 0x09, identifier 0x06 OWNS_CONNECTION, value 0x01 (sendControlCommand → createControlCommandPacket, AACPManager.kt:330).
- OPCODE-SPACE GOTCHA: 0x17 is HEADTRACKING as a top-level AACP opcode (Kotlin Opcodes.HEADTRACKING) but DoubleClickInterval in the *control-command* namespace (Rust aacp.rs:120) — different opcode spaces.
- NEXT: extend capture.py to send OWNS_CONNECTION=1 control command (framing per docs/control_commands.md: `04 00 04 00 09 00 06 00 01 00 00 00`-ish — verify exact bytes) before 0x17 START; buds must be worn + moving (IMU). L2CAP quirk: buds hold the channel ~15s after STOP — wait before reconnecting.

## Head tracking attempts (continuation 13) — EXHAUSTED autonomous hypotheses
Extended capture.py with the FULL takeover: smart-routing hijack (byte-exact from fork's AapHijackRequest) + media info (AapMediaInformation) + ownership re-assert, then 0x17 START — STILL zero frames, and the buds went fully silent to the raw client (even the 0x53 EQ response stopped). With A2DP audio playing during capture (pw-play loop to the buds) — still zero. Remaining unknowns: genuine-Apple-peer takeover details (0x0D/0x0E audio-source negotiation?), firmware-specific TLV variant, or spatial-audio-session state only Apple hosts establish. DEFINITIVE PATH: btmon capture of a REAL iPhone handoff/head-tracking session (needs Hailey's iPhone) — bundle with the handoff live-test. All capture tooling ready at ~/personal/headtracking-capture/capture.py.

## Key facts
- 0x58 START: `04 00 04 00 58 00 00 00 09 00 00 01 82 00 00 00 04 96 00`; STOP: `04 00 04 00 58 00 00 00 02 00 03 01`
- 0x58 audio SDU: bytes [0]=04 [2]=04 u16le@4=0x58 u16le@6=0x0001; 22-byte header then [ts u32le][len u8][AAC AU]*
- AAC-ELD: ASC `F8 E6 30 00`, decoder 48k mono in, output stream 64k, 480 samples/frame
- Client.cpp stock buffer is 1024 — MUST be 4096 for 0x58 (SOCK_SEQPACKET truncates silently)
- Virtual source: module-pipe-source, source_name=AirPodsHiRes, FIFO $XDG_RUNTIME_DIR/librepods-hires.fifo, s16le 64k mono
- Quirks: A2DP reset 800ms after START; stall timeout 2s; conversational awareness should be off while mic active (kavishdevar recommendation)
- Keys: IRK/ENC_KEY auto-captured over AACP (AapPrivateKeys, opcode 0x30/0x31) — saved per-device; popup decrypts the 0x07 advertisement's last 16 bytes (AES-128-ECB) → L/R/Case battery + charging bits
- Advertisement layout: [0]=07 [1]=25 [2]=07 [3..4]=model LE16 (0x2027 = Pro 2 A3064) [5]=status [6]=clear batt [7]=lid counter [8]=color [12..27]=encrypted
- Handoff: see memory 3mxkcnoiv2q22 (HijackRequest 106B, MediaInformation 138B incl. btName → other host's "Moved to" banner, ShowUI 134B, HijackReversed 97B, all opcode 0x10)
- Only one AACP host at a time: PR#655 app and magicpods fight over PSM 0x1001 — kill one before running the other

## Live-test TODOs (need user's hands)
1. Popup: stop `hires-mic-live`, run stock magicpods, connect buds (auto-captures IRK/ENC), open/close case lid → animation near cursor
2. Handoff: needs a second host (iPhone) paired to the buds to observe banner + takeover

## LIVE-VERIFIED (2026-10-10, autonomously)
- **Fork hi-res mic (C++ 0x58 port)**: ran the nix-built fork backend against the buds — parecord capture → 13.0s real audio, 31% energy in 8–16 kHz band = genuine AAC-ELD 64k. The exact binary `nix profile upgrade dotfiles` installs.
- **Fork handoff state parsing**: buds live-reported this laptop + other host 80:96:98:54:E7:93 (info2=0x16 — likely iPhone class); fork parsed + logged it.
- Stale-module cleanup worked live (removed a leftover source from the killed reference app).

## In flight
- ~~hires-mic-port~~ **DONE**: branch `hailey/hires-mic`, MagicPodsCore commit `440a1d6` (submodule tree) — AapHiResMicStart/Stop setters, AapHiResAudio demux+decoder, AapHiResMicCapability (activity monitor, bounded queue, stall watchdog, A2DP reset), Client.cpp 4096 buffer fix, ffmpeg link. Builds clean (nix recipe in flake + /tmp/mpdeps prefetched FetchContent dirs); smoke-tested OK (stale-module unload even verified itself). UNTESTED against live 0x58 capture — needs the buds with the service switched over.
- ~~handoff-port~~ **DONE**: MagicPodsCore branch `hailey/handoff` commit `29bd9fa` — see Handoff row above.
- ~~QML toggles~~ **DONE**: fork root commit `9eb3bf1` (on `hailey/hires-mic`) — BatteryPage.qml hires_mic + handoff switches + Hijack/Release buttons; Backend::setCapabilityObject (setCapability wraps in 'selected' which the map-based SetFromJson payloads don't expect). Full fork builds: frontend `cd ~/personal/magicpods-fork && nix-shell -p cmake ninja pkg-config qt6.qtbase qt6.qtdeclarative qt6.qtwebsockets qt6.qtsvg qt6.qttools qt6.qtwayland --run 'cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -Wno-dev && cmake --build build'` (NOTE: qt6.full removed from nixpkgs — use individual qt packages).
- Remaining port work: handoff packets (smart routing 0x10 formats all extracted, memory 3mxkcnoiv2q22) into MagicPodsCore; optional: head-tracking start packet, conversation-awareness auto-pause during mic, AGC, QML toggle for hires_mic.
- Build recipe note: nix-shell -p cmake ninja pkg-config ffmpeg_8 openssl libpulseaudio bluez systemd sdbus-cpp zlib + FETCHCONTENT_SOURCE_DIR_{SDBUS-CPP,NLOHMANN_JSON,TOMLPLUSPLUS,USOCKETS_CONTENT,UWEBSOCKETS_CONTENT} pointing at /tmp/mpdeps/* (prefetched tags — same pins as dotfiles flake).
- When testing the fork backend live: stop `hires-mic-live` first (PSM 0x1001 conflict). Frontend: rebuild magicpods (fork root CMake) or run stock frontend against the new backend binary (backend on PATH) — frontend spawns backend from PATH, but stock nix magicpodscore shadows; simplest is running the fork's backend build directly with the stock frontend, or rebuilding the frontend from the fork.

