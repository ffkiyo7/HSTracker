#!/bin/bash
# Overlay GPU cost A/B (docs/tasks/perf-p4-overlay-mask.md).
#
# Cycles overlay_perf_mode through 0 1 2 3 while a game is being recorded, so
# every mode gets slices of the same game. HSTracker picks a change up within
# about a second. Each switch is logged as "<unix time> <mode>" so the frame
# time recording can be cut into per-mode segments afterwards.
#
#   0 normal
#   1 overlay window hidden
#   2 window shown, nothing drawn in it
#   3 drawn without the cut-out mask (cut-outs stop working)
#
# Usage: scripts/overlay-perf-ab.sh [seconds per mode, default 30] [log file]
# Ctrl-C puts the tracker back to mode 0.

DOMAIN=net.hearthsim.hstracker
SLICE="${1:-30}"
LOG="${2:-$HOME/Library/Logs/HSTracker/overlay-perf-ab-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG")"

now() {
    python3 -c 'import time; print(f"{time.time():.3f}")'
}

restore() {
    defaults write "$DOMAIN" overlay_perf_mode -int 0
    echo "$(now) 0" >> "$LOG"
    echo "Back to mode 0. Log: $LOG"
    exit 0
}
trap restore INT TERM

echo "Logging switches to $LOG (Ctrl-C to stop)"
while true; do
    for mode in 0 1 2 3; do
        defaults write "$DOMAIN" overlay_perf_mode -int "$mode"
        echo "$(now) $mode" | tee -a "$LOG"
        sleep "$SLICE"
    done
done
