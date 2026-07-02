---
description: Run the full pre-PR verify gate (verify.sh) then code-review the diff
---

Close the AgentStatus dev loop before a PR:

1. Run `scripts/verify.sh` (xcodegen → build → full test suite → perf gate → render snapshots). Fail-fast.
2. If it fails, stop and report exactly which step failed with the relevant output — do not proceed to review.
3. If it passes, remind me to eyeball the freshly rendered snapshots (`/tmp/card-snapshots/`, `/tmp/strip-snapshots/`, `/tmp/menubar-snapshots/`) — and, for interactive UI changes, to launch the Commander board.
4. Then invoke `/code-review` on the current diff and surface its findings.

Do not commit, push, or open a PR as part of this command — it is a gate, not a shipping step.
