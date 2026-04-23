#!/bin/bash
# One-time installer for the TestFlight auto-ship git hook.
# Safe to re-run: overwrites the hook and marks scripts executable.

set -euo pipefail
cd "$(dirname "$0")/.."

HOOK=.git/hooks/post-commit

if [ ! -d .git ]; then
    echo "error: not a git repo (run from meister/ root)" >&2
    exit 1
fi

cat > "$HOOK" <<'HOOK'
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

chmod +x "$HOOK" scripts/auto-ship.sh scripts/ship.sh scripts/build_ipa.sh scripts/deploy_testflight.sh 2>/dev/null || true

echo "✓ Hook installed: $HOOK"
echo "✓ scripts/auto-ship.sh ready"
echo
echo "Test:"
echo "  git commit --allow-empty -m 'test: trigger auto-ship'"
echo "  tail -f build/auto-ship.log"
echo
echo "Disable:  touch .no-auto-ship"
echo "Re-enable: rm .no-auto-ship"
echo "Uninstall: rm $HOOK"
