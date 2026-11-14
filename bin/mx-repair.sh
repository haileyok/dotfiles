#!/usr/bin/env bash
#
# mx-repair.sh — re-bond the Logitech MX Master when it forgets its Bluetooth
# key, without doing the remove/re-add dance by hand.
#
# Why this is needed at all:
#
#   Logitech LE mice hold their bond per host and, when they lose it (link
#   torn down mid-encryption, controller reset, fob reset, dead battery), they
#   come back advertising from a NEW random static address — D4:4E:AA:DA:7C:29
#   -> :2A -> :2C -> :2D, ticking up one octet per cycle. bluetoothd cannot
#   match that address to the stored bond, so the old record is a corpse and a
#   host-initiated connect can never reach the mouse (it just aborts with
#   "le-connection-abort-by-local"). BlueZ's JustWorksRepairing only helps a
#   PEER-initiated re-pair, and an idle HID mouse never initiates one. Hence
#   the manual remove-becomes-pair ritual: it is the only path that clears the
#   stale record and pairs the new identity.
#
# Usage:
#   mx-repair.sh            Scan 20s, then re-bond the mouse
#   mx-repair.sh 45         Same, but scan for 45s (mouse asleep/wiggling)
#
# The mouse must be awake and reachable: if it is off, or sitting on another
# Easy-Switch channel, nothing will advertise and this script tells you so.
#
# Related: MagicPods' BLE scan keeps BlueZ discovery active, which upstream
# documents as breaking auto-reconnect of other BLE devices. Its start is gated
# on [magicpods] animation in ~/.config/magicpods/config.toml; with that true
# the scan runs permanently and this mouse gets starved and dropped. Restart
# MagicPods after changing it (the live toggle does not reliably stop a scan).

set -euo pipefail

SCAN_SECS="${1:-20}"
NAME_RE="MX[[:space:]]+Master"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

command -v bluetoothctl >/dev/null || die "bluetoothctl not found"

# 1. Already connected? Nothing to do.
if bluetoothctl devices Connected 2>/dev/null | grep -qE "$NAME_RE"; then
    info "Already connected:"
    bluetoothctl devices Connected | grep -E "$NAME_RE"
    exit 0
fi

# 2. Everything BlueZ remembers that looks like the mouse (each cycle leaves one
#    more dead identity behind).
mapfile -t known < <(bluetoothctl devices 2>/dev/null | grep -E "$NAME_RE" | awk '{print $2}')
if ((${#known[@]})); then
    info "Known records: ${known[*]}"
fi

# 3. Find what is actually advertising right now — that is the live identity.
info "Scanning ${SCAN_SECS}s for an advertising mouse (wake it now: move it, click a button)..."
mapfile -t advertising < <(
    timeout "$SCAN_SECS" bluetoothctl scan on 2>/dev/null \
        | grep -E "Device [0-9A-F:]{17} .*$NAME_RE" \
        | awk '{print $2}' | sort -u
)
bluetoothctl scan off >/dev/null 2>&1 || true

if ((${#advertising[@]} == 0)); then
    warn "No advertising MX Master found in ${SCAN_SECS}s."
    warn "Check, in this order:"
    warn "  1. mouse is switched on and awake (it stops advertising when idle)"
    warn "  2. Easy-Switch channel is the one paired to this machine"
    warn "  3. it has charge"
    warn "Then re-run: $0 45"
    exit 2
fi

target="${advertising[0]}"
if ((${#advertising[@]} > 1)); then
    warn "Several identities advertising: ${advertising[*]} — using $target"
fi
info "Live identity: $target"

# 4. Drop every stale record for the mouse, including the one we are about to
#    pair (a half-broken bond is what keeps the reconnect aborting).
for mac in "${known[@]-}"; do
    [[ -n "$mac" ]] || continue
    info "Removing stale record $mac"
    bluetoothctl remove "$mac" >/dev/null 2>&1 || warn "  could not remove $mac (probably already gone)"
done
sleep 1

# 5. Pair with an agent registered in the same session. A bare one-shot
#    `bluetoothctl pair` hangs forever waiting for an agent to confirm.
info "Pairing $target"
pair_output=$(
    { printf 'agent on\ndefault-agent\n'; sleep 1; printf 'pair %s\n' "$target"; sleep "${PAIR_WAIT:-12}"; printf 'quit\n'; } \
        | bluetoothctl 2>&1 || true
)
echo "$pair_output" | grep -iE "Pairing|Paired|successful|Failed|error" | sed 's/^/    /' || true

if ! bluetoothctl info "$target" 2>/dev/null | grep -q "Paired: yes"; then
    die "Pairing did not complete. If the mouse shows a 'Paired: no' record it is still advertising — run again with a longer scan ($0 45)."
fi

# 6. Trust it (so BlueZ auto-reconnects instead of waiting for a manual
#    connect) and bring it up.
info "Trusting and connecting"
bluetoothctl trust "$target" >/dev/null 2>&1 || warn "  trust failed"
bluetoothctl connect "$target" >/dev/null 2>&1 || warn "  connect returned an error (it may already be up)"

sleep 2
if bluetoothctl info "$target" 2>/dev/null | grep -q "Connected: yes"; then
    info "Connected: $target"
    grep -iE "MX Master" /proc/bus/input/devices >/dev/null 2>&1 \
        && info "HID input device present"
else
    warn "Paired but not connected. It is bonded now — try again once it wakes, or check dmesg for a controller reset."
fi

# 7. Remind about the preconditions this script cannot fix.
mt7925_control=""
for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] || continue
    if [ "$(cat "$d/idVendor")" = "0e8d" ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = "0717" ]; then
        mt7925_control="$(cat "$d/power/control" 2>/dev/null)"
    fi
done
if [ "$mt7925_control" = "auto" ]; then
    warn "MT7925 is back under USB autosuspend (power/control=auto) — install system/udev/99-mt7925-bt-usb-autosuspend.rules"
fi
if bluetoothctl show 2>/dev/null | grep -q "Discovering: yes"; then
    warn "BlueZ discovery is running (MagicPods' BLE scan) — it starves BLE HID links; set animation=false in ~/.config/magicpods/config.toml and restart MagicPods"
fi
exit 0
