#!/bin/bash
# One-time installer for the TestFlight auto-ship git hooks.
# Fires on commit AND pull (merge or rebase).
# Safe to re-run: overwrites the hooks and marks scripts executable.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
    echo "error: not a git repo (run from meister/ root)" >&2
    exit 1
fi

POST_COMMIT=.git/hooks/post-commit
POST_MERGE=.git/hooks/post-merge
POST_REWRITE=.git/hooks/post-rewrite

# post-commit: fires after a local commit on main
cat > "$POST_COMMIT" <<'HOOK'
#!/bin/bash
# Auto-ship on commits to main.
# Disable: touch <repo>/.no-auto-ship   |   Uninstall: rm .git/hooks/post-commit
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$BRANCH" = "main" ] || exit 0
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/scripts/auto-ship.sh"
[ -x "$SCRIPT" ] || exit 0
nohup "$SCRIPT" </dev/null >/dev/null 2>&1 &
disown
echo "[auto-ship] dispatched in background (pid $!). Tail: build/auto-ship.log"
HOOK

# post-merge: fires after `git pull` (merge mode) when HEAD moved
cat > "$POST_MERGE" <<'HOOK'
#!/bin/bash
# Auto-ship after `git pull` (merge) on main.
# Skips no-op merges (squash flag is "1" only on actual squash merge — we only
# ship if HEAD@{1} differs from HEAD, i.e. the merge brought new code in).
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$BRANCH" = "main" ] || exit 0
PREV=$(git rev-parse 'HEAD@{1}' 2>/dev/null || echo "")
NOW=$(git rev-parse HEAD)
[ -n "$PREV" ] && [ "$PREV" = "$NOW" ] && exit 0
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/scripts/auto-ship.sh"
[ -x "$SCRIPT" ] || exit 0
nohup "$SCRIPT" </dev/null >/dev/null 2>&1 &
disown
echo "[auto-ship] dispatched in background (pid $!). Tail: build/auto-ship.log"
HOOK

# post-rewrite: fires after `git pull --rebase` (and other rewrites). Only act on rebase.
cat > "$POST_REWRITE" <<'HOOK'
#!/bin/bash
# Auto-ship after `git pull --rebase` on main.
# $1 is "rebase" or "amend"; only ship on rebase to avoid double-firing with
# post-commit on `git commit --amend`.
[ "${1:-}" = "rebase" ] || exit 0
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$BRANCH" = "main" ] || exit 0
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/scripts/auto-ship.sh"
[ -x "$SCRIPT" ] || exit 0
nohup "$SCRIPT" </dev/null >/dev/null 2>&1 &
disown
echo "[auto-ship] dispatched in background (pid $!). Tail: build/auto-ship.log"
HOOK

chmod +x "$POST_COMMIT" "$POST_MERGE" "$POST_REWRITE" \
         scripts/auto-ship.sh scripts/ship.sh scripts/build_ipa.sh scripts/deploy_testflight.sh 2>/dev/null || true

echo "✓ Hooks installed:"
echo "  $POST_COMMIT   (commit on main)"
echo "  $POST_MERGE    (git pull merge on main)"
echo "  $POST_REWRITE  (git pull --rebase on main)"
echo "✓ scripts/auto-ship.sh ready"
echo
echo "Test:"
echo "  git commit --allow-empty -m 'test: trigger auto-ship'"
echo "  tail -f build/auto-ship.log"
echo
echo "Disable:  touch .no-auto-ship"
echo "Re-enable: rm .no-auto-ship"
echo "Uninstall: rm $POST_COMMIT $POST_MERGE $POST_REWRITE"
