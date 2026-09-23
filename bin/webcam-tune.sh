#!/usr/bin/env bash
#
# webcam-tune.sh — apply tuned settings to the Framework Webcam Module (2nd Gen).
#
# Tuned values (chosen live against a backlit scene, 2026-09-21):
#   backlight_compensation=2     max foreground exposure bias — fixes
#                                "bright background darkens face" in calls
#   gamma=125                    small shadow lift (default 120; 135 was too
#                                much — washed out the image)
#   sharpness=4                  slightly above default 3
#   power_line_frequency=2       60Hz (US) — kills indoor light-flicker banding
#   exposure_dynamic_framerate=0 keep 30fps in low light instead of slowing
#                                sensor exposure (smeary-slideshow prevention)
#
# UVC controls reset when the camera re-enumerates (reboot/suspend), so this is
# wired into sway's exec_always. Controls can be changed mid-stream, so it is
# also safe to run while a call is active. Safe to re-run.
#
# Usage: webcam-tune.sh [device]

set -euo pipefail

DEV="${1:-/dev/video0}"

# Find the Framework webcam if the given device doesn't look right
if ! v4l2-ctl -d "$DEV" -D 2>/dev/null | grep -q 'Laptop Webcam Module'; then
    DEV=""
    for d in /dev/video*; do
        if v4l2-ctl -d "$d" -D 2>/dev/null | grep -q 'Laptop Webcam Module'; then
            DEV="$d"
            break
        fi
    done
    if [ -z "$DEV" ]; then
        echo "⚠ Framework webcam not found in /dev/video*"
        exit 1
    fi
fi

v4l2-ctl -d "$DEV" --set-ctrl \
    backlight_compensation=2,gamma=125,sharpness=4,power_line_frequency=2,exposure_dynamic_framerate=0
echo "✓ Webcam settings applied to $DEV"
v4l2-ctl -d "$DEV" --get-ctrl backlight_compensation,gamma,sharpness,power_line_frequency,exposure_dynamic_framerate
