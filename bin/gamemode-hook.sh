#!/usr/bin/env bash
#
# gamemode-hook.sh — GameMode start/end hook (see gamemode/gamemode.ini).
#
#   gamemode-hook.sh start   Remember the current PPD profile, switch to balanced
#   gamemode-hook.sh end     Restore the remembered profile
#
# Why balanced rather than performance: on this Framework 13 the CPU and iGPU
# share one power/thermal budget. PPD performance lets the cores boost hard
# and hit their thermal limit, which throttles the iGPU. Balanced keeps the
# cores cool and leaves the budget to the GPU (~1.4 GHz -> ~2.3 GHz sustained
# in Slay the Spire 2 at 4K).
#
# Profile switching goes through power-profiles.sh so the eDP-1 refresh rate
# bundle stays consistent with the waybar module / $mod+p.

set -uo pipefail

PP="$HOME/dotfiles/bin/power-profiles.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-prev-profile"
GAME_PROFILE="balanced"

# gdbus rather than notify-send (not installed); matches voice-type.py.
notify() {
    gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "GameMode" 0 "" "GameMode" "$1" "[]" "{}" 3000 >/dev/null 2>&1 || true
    # Refresh the waybar power-profile module (🎮 badge) right away.
    pkill -RTMIN+8 waybar 2>/dev/null || true
}

case "${1:-}" in
    start)
        current=$(powerprofilesctl get 2>/dev/null || echo balanced)
        echo "$current" > "$STATE"
        if [ "$current" != "$GAME_PROFILE" ]; then
            "$PP" "$GAME_PROFILE" >/dev/null
        fi
        notify "On — power profile: ${GAME_PROFILE} (was ${current})"
        ;;
    end)
        prev=$(cat "$STATE" 2>/dev/null || echo "")
        rm -f "$STATE"
        if [ -n "$prev" ] && [ "$prev" != "$(powerprofilesctl get 2>/dev/null)" ]; then
            "$PP" "$prev" >/dev/null
        fi
        notify "Off — power profile: ${prev:-unchanged}"
        ;;
    *)
        echo "Usage: $0 {start|end}" >&2
        exit 1
        ;;
esac
