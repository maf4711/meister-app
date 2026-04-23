#!/bin/bash
# Auto-ship wrapper: runs ship.sh in the background, logs, and notifies.
# Called by .git/hooks/post-commit when a commit lands on main.
#
# Off-switch:  touch .no-auto-ship   (in repo root)
# Off again:   rm .no-auto-ship

set -uo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$PWD"
LOCK="$REPO_ROOT/.auto-ship.lock"
LOG="$REPO_ROOT/build/auto-ship.log"
mkdir -p "$REPO_ROOT/build"

notify() {
    local title="$1" msg="$2"
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
}

if [ -f "$REPO_ROOT/.no-auto-ship" ]; then
    echo "[auto-ship] .no-auto-ship present, skipping" >> "$LOG"
    exit 0
fi

if [ -f "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "[auto-ship] already running (pid $PID), skipping" >> "$LOG"
        notify "Meister ship" "Skipped — previous build still running (pid $PID)"
        exit 0
    fi
    rm -f "$LOCK"
fi

echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

NOTES=$(git log -1 --pretty=%B | head -c 4000)
SHA=$(git rev-parse --short HEAD)

{
    echo
    echo "========================================="
    echo "[auto-ship] $(date '+%Y-%m-%d %H:%M:%S')  commit $SHA"
    echo "========================================="
} >> "$LOG"

notify "Meister ship" "Build started for $SHA"

if ./scripts/ship.sh "$NOTES" >> "$LOG" 2>&1; then
    BUILD=$(grep -oE 'build [0-9]+ live' "$LOG" | tail -1 | awk '{print $2}')
    notify "Meister ship ✓" "Build ${BUILD:-?} live on TestFlight"
    echo "[auto-ship] success" >> "$LOG"
else
    RC=$?
    notify "Meister ship ✗" "Build failed (rc=$RC) — see build/auto-ship.log"
    echo "[auto-ship] FAILED rc=$RC" >> "$LOG"
    exit $RC
fi
