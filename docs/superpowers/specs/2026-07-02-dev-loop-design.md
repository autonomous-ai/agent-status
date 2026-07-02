# AgentStatus dev loop — design

**Date:** 2026-07-02
**Status:** approved design, pending spec review

## Problem

The repo has real quality tooling (unit tests, a perf gate, headless snapshot render tests, a launchable Commander board) but no documented loop tying them together and no automation. Today the build → test → perf → visual → review cycle lives only in a human's head and scattered CLAUDE.md commands. Two consequences:

- Easy to skip a gate that mattered (e.g. forget `xcodegen generate` after adding a file, or forget the `coreEqual` invariant so the UI silently stops updating).
- Easy to *over*-run gates — running the full ~2-minute suite and perf benchmark on a doc-only or single-view tweak.

## Goal

A repeatable, mostly-documented dev loop for iterating on the AgentStatus app itself, with lightweight automation for the highest-value gates. **Hybrid** form: the documented loop is the source of truth; one script + one slash command collapse the heavy gates into a single invocation. No hooks, no CI now — but the script is authored so it can drop into a GitHub Action later.

Non-goals: GitHub Actions/CI, Claude Code hooks, changing the existing test or perf infrastructure.

## The loop

Documented **inline in CLAUDE.md** (a new "## Dev loop" section), because the user wants one place to look and future sessions already read CLAUDE.md.

```
0. FRAME   Non-trivial change? → brainstorming → writing-plans. Feature/bugfix → TDD (test first).
1. CHANGE  Edit source. Added/removed a file? → edit project.yml, then `xcodegen generate`.
           Added a field a view reads? → add it to EnrichedSession.coreEqual + its test
           (EnrichedSessionCoreEqualTests), or the UI silently won't update.
2. BUILD   xcodebuild ... build — fast compile check.
3. TEST    xcodebuild ... test, iterating with -only-testing: on the class you touched.
4. PERF*   Touched Watching/ or transcript parsing? → scripts/perf-check.sh.
5. VISUAL* Touched UI/? → run the *SnapshotRenderTests, eyeball /tmp/*-snapshots/;
           launch --commander for interactive changes.
6. REVIEW  /code-review on the diff before PR.
7. SHIP    finishing-a-development-branch → commit + PR.

* conditional gate — runs only when the change touches that area (see decision table).
```

### Gate-selection decision table

Keeps the loop cheap by default, thorough when it matters.

| What you touched | Build | Tests | Perf | Snapshots | Commander |
|---|---|---|---|---|---|
| `Model/`, `Store/` | ✓ | ✓ | — | — | — |
| `Watching/`, parsing (`ClaudeCode/`) | ✓ | ✓ | ✓ | — | — |
| `UI/` (any view) | ✓ | ✓ | — | ✓ | on interactive change |
| `App/`, `Util/`, `Providers/` plumbing | ✓ | ✓ | — | — | — |
| `project.yml` / file add/remove | ✓ (after `xcodegen generate`) | ✓ | — | — | — |
| Docs / comments only | — | — | — | — | — |
| **Before any PR** | full `scripts/verify.sh` + `/code-review` | | | | |

## Automation artifacts

### `scripts/verify.sh`

One-shot pre-PR gate. Sequence, fail-fast (`set -euo pipefail`), mirroring the exact commands already in CLAUDE.md and `perf-check.sh`:

1. `xcodegen generate`
2. Build: `xcodebuild -project AgentStatus.xcodeproj -scheme AgentStatus -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
3. Test: `xcodebuild -project AgentStatus.xcodeproj -scheme AgentStatus -destination 'platform=macOS' test`
4. Perf: `scripts/perf-check.sh` (already gates to 2x of `perf-baseline.txt` = 0.45s)
5. Snapshots: run the render test classes so `/tmp/card-snapshots/`, `/tmp/strip-snapshots/`, `/tmp/*-snapshots/` are fresh; print the paths for eyeball review.

Design notes:
- `cd "$(dirname "$0")/.."` like `perf-check.sh`, so it runs from anywhere.
- Steps 3 and 4 both run `xcodebuild test`; keep them separate (perf-check is self-contained and independently useful) rather than merging — clarity over a few saved seconds. Acceptable, documented redundancy.
- Prints a clear PASS/where-to-look summary at the end. Snapshot review is inherently human, so verify.sh renders them and points at them; it does not try to judge them.
- No signing of the built `.app` (that's a release step, not a verify step).
- Authored as a plain portable bash script so a future `.github/workflows/ci.yml` can call it directly.

### `.claude/commands/verify.md`

A project slash command (`/verify`) whose body instructs: run `scripts/verify.sh`, report results, then if it passes run `/code-review` on the diff and surface findings. Collapses "close the loop" into one command. (`.claude/` exists but has no `commands/` dir yet — this creates it.)

## CLAUDE.md changes

- Add a `## Dev loop` section containing the loop steps + decision table above.
- Add `scripts/verify.sh` and the `/verify` command to the Commands section.
- Cross-reference the existing `coreEqual` and `xcodegen generate` gotchas from the loop's CHANGE step (they already exist in the doc; the loop points at them rather than duplicating).

## Testing / verification of this change

- `scripts/verify.sh` is self-verifying: running it once end-to-end (and confirming a green build+test+perf, plus snapshot dirs populated) proves it works.
- `/verify` command: invoke once, confirm it runs the script and hands off to `/code-review`.
- No new Swift code, so no new unit tests.

## Risks / trade-offs

- **Redundant `xcodebuild test`** in verify.sh (steps 3 + 4). Chosen for clarity; wall-clock cost is small on this suite.
- **Discipline, not enforcement.** Without hooks/CI nothing *forces* the loop. Mitigation: the `/verify` one-liner lowers friction enough that running it is easier than not; CI seam left open.
- **Snapshot review stays manual.** By design — the tests render, a human eyeballs. verify.sh just guarantees freshness.
