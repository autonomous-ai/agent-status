#!/usr/bin/env bash
# Pre-PR verify gate. Runs the full dev-loop in order, fail-fast:
#   xcodegen → build → test → perf → snapshot render.
# Snapshot review is inherently human: this renders them fresh and prints
# where they landed; it does not judge them.
#
# Usage:
#   scripts/verify.sh
#
# Exit 0 only when build, tests, and the perf gate all pass. Authored as a
# plain portable script so a future CI workflow can call it directly.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJ=(-project AgentStatus.xcodeproj -scheme AgentStatus)

echo "==> [1/5] xcodegen generate"
xcodegen generate

echo "==> [2/5] build (Release, ad-hoc signed)"
xcodebuild "${PROJ[@]}" -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

echo "==> [3/5] test (full suite)"
xcodebuild "${PROJ[@]}" -destination 'platform=macOS' test

echo "==> [4/5] perf gate"
scripts/perf-check.sh

echo "==> [5/5] render UI snapshots"
xcodebuild "${PROJ[@]}" -destination 'platform=macOS' test \
  -only-testing:AgentStatusTests/CardSnapshotRenderTests \
  -only-testing:AgentStatusTests/DetailStripSnapshotRenderTests \
  -only-testing:AgentStatusTests/MenuBarSnapshotRenderTests

cat <<'EOF'

==> VERIFY PASSED (build + tests + perf all green)
Eyeball the freshly rendered snapshots before opening a PR:
  /tmp/card-snapshots/
  /tmp/strip-snapshots/
  /tmp/menubar-snapshots/
For interactive UI changes also launch the Commander board:
  pkill -x AgentStatus; open build/Build/Products/Release/AgentStatus.app --args --commander
EOF
