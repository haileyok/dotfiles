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
#
# NOTE: charge thresholds are set in the BIOS on this machine (85% cap).
# The 13 Pro does not expose charge_control_end_threshold via sysfs, unlike
# the Framework 16, so this script no longer manages charge thresholds.

set -euo pipefail

BAT="/sys/class/power_supply/BAT1"

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
}

case "${1:-status}" in
    status)
        get_status
        ;;
    cycle)
        cycle_profile
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
        echo "Usage: $0 {status|performance|balanced|power-saver}"
        exit 1
        ;;
esac
