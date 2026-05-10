#!/bin/bash
# Send Tom a short iMessage summary when a new TestFlight build goes live.
# Called by auto-ship.sh after ship.sh succeeds.
#
# Off-switch:  touch <repo>/.no-tom-notify   (stays silent until removed)
#
# Usage:  notify-tom.sh "Build 28 live: Foto-Preview-Button + Kontakte-Permission..."

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOM_HANDLE="t.brohl@icloud.com"
LOG="$REPO_ROOT/build/auto-ship.log"

if [ -f "$REPO_ROOT/.no-tom-notify" ]; then
    echo "[notify-tom] disabled via .no-tom-notify" >> "$LOG" 2>/dev/null
    exit 0
fi

MESSAGE="${1:-Meister: neuer TestFlight-Build live. Tippe in TestFlight 'Aktualisieren'.}"

# Trim to 280 chars — iMessage doesn't have a hard cap but mobile preview cuts.
MESSAGE="${MESSAGE:0:280}"

# Send via Messages.app + AppleScript. Requires Messages.app to be signed in
# with iMessage. The "buddy" lookup falls back across services automatically.
osascript >> "$LOG" 2>&1 <<APPLESCRIPT
tell application "Messages"
    set targetService to 1st service whose service type = iMessage
    set targetBuddy to buddy "$TOM_HANDLE" of targetService
    send "$MESSAGE" to targetBuddy
end tell
APPLESCRIPT

if [ $? -eq 0 ]; then
    echo "[notify-tom] sent to $TOM_HANDLE: $MESSAGE" >> "$LOG"
else
    echo "[notify-tom] send failed" >> "$LOG"
fi
