#!/usr/bin/env bash
#
# volume.sh — volume keys that work with the EasyEffects chain.
#
# Problem this solves: with EasyEffects active, the default sink is
# easyeffects_sink. Changing ITS volume moves the waybar percentage but does
# not change the audible level (the real attenuation happens on the hardware
# sink EE outputs into). This script adjusts the *hardware* sink and syncs the
# easyeffects_sink volume so the waybar display matches what you hear.
#
# When EasyEffects is not running, it falls back to @DEFAULT_SINK@ (normal
# behavior, no sync needed).
#
# Usage: volume.sh {up|down|mute}

set -euo pipefail

STEP=5
EE_SINK="easyeffects_sink"

find_hw_sink() {
    # The sink that EasyEffects' final output node links into
    pw-dump 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
nodes = {}
for o in d:
    if o.get('type') == 'PipeWire:Interface:Node':
        p = o.get('info', {}).get('props', {})
        nodes[o['id']] = p.get('node.name', '')
for o in d:
    if 'PipeWire:Interface:Link' in o.get('type', ''):
        i = o.get('info', {})
        out, inp = i.get('output-node-id'), i.get('input-node-id')
        if nodes.get(out) == 'ee_soe_output_level':
            print(nodes.get(inp, ''))
            break
" 2>/dev/null
}

sink_exists() {
    pactl list sinks 2>/dev/null | grep -q "Name: $1"
}

# Figure out the real target
HW=$(find_hw_sink)
if [ -n "$HW" ] && sink_exists "$HW" && sink_exists "$EE_SINK"; then
    TARGET="$HW"; SYNC=1
else
    TARGET="@DEFAULT_SINK@"; SYNC=0
fi

get_volume_pct() {
    pactl list sinks | awk -v t="$1" '$0 ~ "Name: "t {f=1} f && /Volume:/ {for(i=1;i<=NF;i++) if($i ~ /%/) {sub(/%/,"",$i); print $i; exit}}'
}

is_muted() {
    pactl list sinks | awk -v t="$1" '$0 ~ "Name: "t {f=1} f && /Mute:/ {print $2; exit}'
}

case "${1:-}" in
    up)
        pactl set-sink-volume "$TARGET" "+${STEP}%"
        ;;
    down)
        pactl set-sink-volume "$TARGET" "-${STEP}%"
        ;;
    mute)
        pactl set-sink-mute "$TARGET" toggle
        ;;
    *)
        echo "Usage: $0 {up|down|mute}"
        exit 1
        ;;
esac

# Sync the display sink (easyeffects_sink) so waybar matches reality.
# Its volume does not scale audio (verified), so this is purely cosmetic.
if [ "$SYNC" = "1" ]; then
    V=$(get_volume_pct "$HW")
    [ -n "$V" ] && pactl set-sink-volume "$EE_SINK" "${V}%"
    M=$(is_muted "$HW")
    [ "$M" = "yes" ] && pactl set-sink-mute "$EE_SINK" 1 || pactl set-sink-mute "$EE_SINK" 0
fi
