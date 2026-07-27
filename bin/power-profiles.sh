#!/usr/bin/env bash
#
# power-profiles.sh — Toggle between power profiles and battery charge thresholds.
# Requires power-profiles-daemon (zypper install power-profiles-daemon).
#
# Usage:
#   power-profiles.sh status          Show current profile and charge threshold
#   power-profiles.sh performance     Set high-performance mode (charge to 100%)
#   power-profiles.sh balanced        Set balanced mode (charge to 90%)
#   power-profiles.sh power-saver     Set power-saver mode (charge to 80%)
#
# Framework laptops support both power-profiles-daemon and charge thresholds
# via /sys/class/power_supply/BAT1/charge_control_end_threshold.

set -euo pipefail

BAT="/sys/class/power_supply/BAT1"
THRESHOLD_FILE="${BAT}/charge_control_end_threshold"

get_threshold() {
    if [ -f "$THRESHOLD_FILE" ]; then
        cat "$THRESHOLD_FILE"
    else
        echo "n/a"
    fi
}

get_status() {
    local status capacity profile threshold
    status=$(cat "${BAT}/status" 2>/dev/null || echo "n/a")
    capacity=$(cat "${BAT}/capacity" 2>/dev/null || echo "n/a")
    profile=$(powerprofilesctl get 2>/dev/null || echo "n/a")
    threshold=$(get_threshold)

    echo "Battery:    ${capacity}% (${status})"
    echo "Profile:    ${profile}"
    echo "Threshold:  ${threshold}%"
}

set_profile() {
    local profile="$1"
    powerprofilesctl set "$profile"
    echo "✓ Power profile set to: ${profile}"
}

set_threshold() {
    local threshold="$1"
    if [ -w "$THRESHOLD_FILE" ]; then
        echo "$threshold" | sudo tee "$THRESHOLD_FILE" > /dev/null
        echo "✓ Charge threshold set to: ${threshold}%"
    else
        echo "⚠ Charge threshold not supported on this device"
    fi
}

case "${1:-status}" in
    status)
        get_status
        ;;
    performance)
        set_profile performance
        set_threshold 100
        ;;
    balanced)
        set_profile balanced
        set_threshold 90
        ;;
    power-saver|powersaver|saver)
        set_profile power-saver
        set_threshold 80
        ;;
    *)
        echo "Usage: $0 {status|performance|balanced|power-saver}"
        exit 1
        ;;
esac
