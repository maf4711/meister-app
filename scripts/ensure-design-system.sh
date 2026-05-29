#!/bin/bash
# Guard: ensure the MeradOSDesign4 local sibling SPM exists before xcodegen or build.
# Purpose: turn a cryptic "package not found" failure (from the hardcoded path in
# project.yml) into an early, actionable FATAL with remediation guidance.
#
# This implements Track 2 (P0) of the Meister Remediation Program:
# - Documented local SPM with bootstrap guard (no behavior change to builds yet).
# - Supports worktrees, CI, and other machines via LOCAL_DESIGN_PATH.
#
# Future: a later track may promote this to a remote SPM or vendored copy.
#
# Usage (from anywhere):
#   ./scripts/ensure-design-system.sh
#   LOCAL_DESIGN_PATH=/absolute/path/to/merados-design4 ./scripts/ensure-design-system.sh
#
# All other scripts/ in this repo use the same "cd to project root" pattern so
# relative paths match project.yml expectations exactly.

set -euo pipefail
cd "$(dirname "$0")/.."

DESIGN_PATH="${LOCAL_DESIGN_PATH:-../meradOS/merados-design4}"

if [ ! -d "$DESIGN_PATH" ]; then
  echo "FATAL: MeradOSDesign4 not found at $DESIGN_PATH"
  echo "This is currently a hard local sibling dependency declared in project.yml."
  echo "See README.md (Install → local build instructions) for details and override."
  exit 1
fi

echo "✓ MeradOSDesign4 present at $DESIGN_PATH"
