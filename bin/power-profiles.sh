#!/usr/bin/env bash
#
# power-profiles.sh — Toggle power profiles (Framework 13 Pro).
# Requires power-profiles-daemon (sudo zypper install power-profiles-daemon).
#
# Usage:
#   power-profiles.sh status          Show current profile and battery state
#   power-profiles.sh cycle           Cycle: power-saver -> balanced -> performance
#   power-profiles.sh performance     Set high-performance mode
#   power-profiles.sh balanced        Set balanced mode
#   power-profiles.sh power-saver     Set power-saver mode
#   power-profiles.sh pick            wofi picker (waybar on-click)
#   power-profiles.sh waybar          JSON status for waybar custom/power-profile
#   power-profiles.sh panel [0-4]     Show/set the power-saver panel power
#                                     savings (ABM) level; 0 = off, 4 = max.
#                                     Only used on battery; AC is always 0.
#   power-profiles.sh watch           Re-apply the panel level on AC plug/unplug
#                                     (long-running; started by sway)
#   power-profiles.sh sync            Re-apply display settings for the current
#                                     profile (run by sway on reload; never
#                                     changes the profile itself)
#
# Switching is always manual. Each profile is a bundle:
#   performance  (plugged in)  PPD performance, eDP-1 at 120 Hz
#   balanced                   PPD balanced,    eDP-1 at 120 Hz
#   power-saver  (on battery)  PPD power-saver, eDP-1 at 60 Hz, VRR off (so PSR
#                              can engage), panel power savings on battery
# 60 Hz on the internal panel is one of the biggest single battery wins.
# PPD's own per-profile tuning (CPU EPP, platform_profile, and — if enabled —
# the amdgpu_panel_power action) comes along with the profile.
#
# NOTE: charge thresholds are set in the BIOS on this machine (85% cap).
# The 13 Pro does not expose charge_control_end_threshold via sysfs, unlike
# the Framework 16, so this script no longer manages charge thresholds.

set -euo pipefail

BAT="/sys/class/power_supply/BAT1"
PANEL="eDP-1"
PANEL_RES="2880x1920"   # keep in sync with sway/config.d/monitors

panel_hz_for() {
    case "$1" in
        power-saver) echo 60 ;;
        *)           echo 120 ;;
    esac
}

# amdgpu panel power savings (ABM): 0 = off, 1..4 = progressively more
# aggressive backlight reduction with contrast compensation (costs some colour
# accuracy). Needs system/udev/90-amdgpu-panel-power-savings.rules for write
# access and system/power-profiles-daemon/block-panel-power.conf so PPD's own
# battery-level-based action doesn't overwrite it.
#
# The power-saver level defaults to 3 and can be changed (and persisted) with
# `power-profiles.sh panel <0-4>`, which writes PANEL_LEVEL_FILE.
PANEL_LEVEL_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/power-profiles/panel-power-savings"

saver_panel_level() {
    local level
    level=$(cat "$PANEL_LEVEL_FILE" 2>/dev/null || echo 3)
    case "$level" in
        [0-4]) echo "$level" ;;
        *)     echo 3 ;;
    esac
}

on_battery() {
    # ACAD is the laptop's charger (USB-C entries include downstream roles).
    [ "$(cat /sys/class/power_supply/ACAD/online 2>/dev/null)" != "1" ]
}

# Only dim on battery: plugged in always means 0, whatever the profile.
panel_power_savings_for() {
    if [ "$1" = "power-saver" ] && on_battery; then
        saver_panel_level
    else
        echo 0
    fi
}

# `panel [0-4]`: show or set the power-saver panel power savings level.
set_panel_level() {
    local level="${1:-}" profile
    if [ -z "$level" ]; then
        echo "Power-saver panel power savings: $(saver_panel_level) (current: $(cat /sys/class/drm/card*-"${PANEL}"/amdgpu/panel_power_savings 2>/dev/null | head -1 || echo n/a))"
        return 0
    fi
    case "$level" in
        [0-4]) ;;
        *) echo "Usage: $0 panel [0-4]" >&2; exit 1 ;;
    esac
    mkdir -p "$(dirname "$PANEL_LEVEL_FILE")"
    echo "$level" > "$PANEL_LEVEL_FILE"
    echo "✓ Power-saver panel power savings set to ${level}"
    profile=$(powerprofilesctl get 2>/dev/null || echo "")
    if [ "$profile" = "power-saver" ] && on_battery; then
        apply_panel_power "$profile"
    else
        echo "  (used in power-saver on battery; now: ${profile:-unknown}, $(on_battery && echo battery || echo AC))"
    fi
}

# `watch`: re-apply the panel level whenever the charger is plugged/unplugged.
# Event-driven (blocks on UPower's D-Bus signal), so it costs nothing at idle.
# Started once from sway (config.d/monitors); a lock keeps it single-instance.
watch_power() {
    local lock="${XDG_RUNTIME_DIR:-/tmp}/power-profiles-watch.lock"
    exec 9>"$lock"
    flock -n 9 || { echo "watch already running"; return 0; }
    gdbus monitor --system --dest org.freedesktop.UPower \
            --object-path /org/freedesktop/UPower 2>/dev/null |
        while IFS= read -r line; do
            case "$line" in
                *OnBattery*)
                    apply_panel_power "$(powerprofilesctl get 2>/dev/null || echo balanced)" >/dev/null
                    ;;
            esac
        done
}

apply_panel_power() {
    local level f applied=0
    level=$(panel_power_savings_for "$1")
    for f in /sys/class/drm/card*-"${PANEL}"/amdgpu/panel_power_savings; do
        [ -w "$f" ] || continue
        echo "$level" > "$f" 2>/dev/null && applied=1
    done
    if [ "$applied" = 1 ]; then
        echo "✓ ${PANEL} panel power savings: ${level}"
    fi
}

# Set the internal panel's refresh rate to match a profile. No-op outside sway
# or if the panel isn't present (e.g. lid closed on a dock).
apply_display() {
    local hz
    apply_panel_power "$1"
    hz=$(panel_hz_for "$1")
    command -v swaymsg >/dev/null 2>&1 || return 0
    swaymsg -t get_outputs -r 2>/dev/null | grep -q "\"${PANEL}\"" || return 0
    if swaymsg output "$PANEL" mode "${PANEL_RES}@${hz}Hz" >/dev/null 2>&1; then
        echo "✓ ${PANEL} refresh: ${hz} Hz"
    else
        echo "⚠ could not set ${PANEL} to ${hz} Hz"
    fi
    local vrr
    vrr=$(panel_vrr_for "$1")
    if swaymsg output "$PANEL" adaptive_sync "$vrr" >/dev/null 2>&1; then
        echo "✓ ${PANEL} adaptive sync: ${vrr}"
    fi
}

# VRR (adaptive sync) keeps amdgpu from entering Panel Self Refresh on the
# internal panel: measured psr_state stayed 0 with VRR on and cycled into
# self-refresh with it off. PSR is the bigger idle win, so power-saver turns
# VRR off; the other profiles keep it (matches sway/config.d/monitors).
panel_vrr_for() {
    case "$1" in
        power-saver) echo off ;;
        *)           echo on ;;
    esac
}

get_status() {
    local status capacity profile threshold
    status=$(cat "${BAT}/status" 2>/dev/null || echo "n/a")
    capacity=$(cat "${BAT}/capacity" 2>/dev/null || echo "n/a")
    if command -v powerprofilesctl >/dev/null 2>&1; then
        profile=$(powerprofilesctl get 2>/dev/null || echo "n/a")
    else
        profile="power-profiles-daemon not installed"
    fi

    echo "Battery:   ${capacity}% (${status})"
    echo "Profile:   ${profile}"
    if command -v swaymsg >/dev/null 2>&1; then
        echo "Panel:     $(swaymsg -t get_outputs -r 2>/dev/null | jq -r --arg p "$PANEL" '.[] | select(.name==$p) | "\(.current_mode.refresh/1000|floor) Hz"' 2>/dev/null || echo n/a)"
    fi
    echo "Charge cap: BIOS-managed"
}

# Desktop notification via gdbus (notify-send isn't installed; same approach
# as bin/voice-type.py).
notify() {
    gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "Power profile" 0 "" "Power profile" "$1" "[]" "{}" 2500 \
        >/dev/null 2>&1 || true
}

profile_icon() {
    case "$1" in
        performance) echo "⚡" ;;
        balanced)    echo "⚖" ;;
        power-saver) echo "🌙" ;;
        *)           echo "?" ;;
    esac
}

profile_title() {
    case "$1" in
        performance) echo "Performance" ;;
        balanced)    echo "Balanced" ;;
        power-saver) echo "Power saver" ;;
        *)           echo "$1" ;;
    esac
}

# JSON for the waybar custom/power-profile module (return-type: json).
# class = profile name (+ " gamemode" while a GameMode session is active) so
# waybar/style.css can colour it.
waybar_status() {
    local profile icon text tooltip class bat_status bat_cap
    profile=$(powerprofilesctl get 2>/dev/null || echo "unknown")
    icon=$(profile_icon "$profile")
    text="$icon"
    class="$profile"
    bat_status=$(cat "${BAT}/status" 2>/dev/null || echo "n/a")
    bat_cap=$(cat "${BAT}/capacity" 2>/dev/null || echo "?")
    tooltip="Power profile: $(profile_title "$profile") (battery ${bat_cap}%, ${bat_status}). Click to choose."
    if command -v gamemoded >/dev/null 2>&1 && gamemoded -s 2>/dev/null | grep -q "is active"; then
        text="$icon 🎮"
        class="$profile gamemode"
        tooltip="$tooltip GameMode active: profile is restored when the game exits."
    fi
    jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: ($class | split(" "))}'
}

# wofi picker, mirroring voice-type.py --pick-backend.
pick_profile() {
    local current choice profile p options=""
    current=$(powerprofilesctl get 2>/dev/null || echo "")
    for p in performance balanced power-saver; do
        options+="$(profile_icon "$p")  $(profile_title "$p")"
        [ "$p" = "$current" ] && options+="  (current)"
        options+=$'\n'
    done
    choice=$(printf '%s' "$options" | wofi --dmenu --prompt "Power profile" --lines 3 2>/dev/null) || true
    case "$choice" in
        *Performance*)   profile=performance ;;
        *Balanced*)      profile=balanced ;;
        *"Power saver"*) profile=power-saver ;;
        *)               return 0 ;;
    esac
    [ "$profile" = "$current" ] && return 0
    set_profile "$profile" >/dev/null
    notify "$(profile_icon "$profile") $(profile_title "$profile")"
    pkill -RTMIN+8 waybar 2>/dev/null || true
}

set_profile() {
    local profile="$1"
    if ! command -v powerprofilesctl >/dev/null 2>&1; then
        echo "⚠ powerprofilesctl not found — install power-profiles-daemon first:"
        echo "  sudo zypper install power-profiles-daemon"
        exit 1
    fi
    powerprofilesctl set "$profile"
    echo "✓ Power profile set to: ${profile}"
    apply_display "$profile"
    refresh_waybar
}

# waybar's custom/power-profile only polls every 30 s; poke it (signal 8) so
# the icon follows every change made through this script.
refresh_waybar() {
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
}

cycle_profile() {
    if ! command -v powerprofilesctl >/dev/null 2>&1; then
        echo "⚠ powerprofilesctl not found — install power-profiles-daemon first:"
        echo "  sudo zypper install power-profiles-daemon"
        exit 1
    fi
    local current next
    current=$(powerprofilesctl get 2>/dev/null || echo "balanced")
    case "$current" in
        power-saver) next="balanced" ;;
        balanced)    next="performance" ;;
        performance) next="power-saver" ;;
        *)           next="balanced" ;;
    esac
    powerprofilesctl set "$next"
    echo "✓ Power profile: ${current} -> ${next}"
    apply_display "$next"
    refresh_waybar
}

case "${1:-status}" in
    status)
        get_status
        ;;
    cycle)
        cycle_profile
        ;;
    waybar)
        waybar_status
        ;;
    pick)
        pick_profile
        ;;
    sync)
        apply_display "$(powerprofilesctl get 2>/dev/null || echo balanced)"
        ;;
    panel)
        set_panel_level "${2:-}"
        ;;
    watch)
        watch_power
        ;;
    performance)
        set_profile performance
        ;;
    balanced)
        set_profile balanced
        ;;
    power-saver|powersaver|saver)
        set_profile power-saver
        ;;
    *)
        echo "Usage: $0 {status|cycle|performance|balanced|power-saver|sync|waybar|pick|panel [0-4]|watch}"
        exit 1
        ;;
esac
