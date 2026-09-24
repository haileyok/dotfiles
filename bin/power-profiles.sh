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
#   power-profiles.sh sync            Re-apply display settings for the current
#                                     profile (run by sway on reload; never
#                                     changes the profile itself)
#
# Switching is always manual. Each profile is a bundle:
#   performance  (plugged in)  PPD performance, eDP-1 at 120 Hz
#   balanced                   PPD balanced,    eDP-1 at 120 Hz
#   power-saver  (on battery)  PPD power-saver, eDP-1 at 60 Hz
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

# Set the internal panel's refresh rate to match a profile. No-op outside sway
# or if the panel isn't present (e.g. lid closed on a dock).
apply_display() {
    local hz
    hz=$(panel_hz_for "$1")
    command -v swaymsg >/dev/null 2>&1 || return 0
    swaymsg -t get_outputs -r 2>/dev/null | grep -q "\"${PANEL}\"" || return 0
    if swaymsg output "$PANEL" mode "${PANEL_RES}@${hz}Hz" >/dev/null 2>&1; then
        echo "✓ ${PANEL} refresh: ${hz} Hz"
    else
        echo "⚠ could not set ${PANEL} to ${hz} Hz"
    fi
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
}

case "${1:-status}" in
    status)
        get_status
        ;;
    cycle)
        cycle_profile
        ;;
    sync)
        apply_display "$(powerprofilesctl get 2>/dev/null || echo balanced)"
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
        echo "Usage: $0 {status|cycle|performance|balanced|power-saver|sync}"
        exit 1
        ;;
esac
