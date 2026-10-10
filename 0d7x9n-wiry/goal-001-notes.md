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

