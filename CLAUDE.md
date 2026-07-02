# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS menu-bar app (macOS 14+, Swift 6, strict concurrency, SwiftUI + AppKit) that watches the on-disk state Claude Code writes locally (`~/.claude/sessions/<pid>.json` + `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`) and surfaces live session status. Zero network calls. The Xcode project is generated — never edit `AgentStatus.xcodeproj` by hand; edit `project.yml` and re-run `xcodegen generate` (required after adding/removing files).

## Commands

```bash
xcodegen generate                                    # regenerate .xcodeproj (after file adds/removes)

# Build the app (Release, ad-hoc signed)
xcodebuild -project AgentStatus.xcodeproj -scheme AgentStatus -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - build/Build/Products/Release/AgentStatus.app

# Run all tests
xcodebuild -project AgentStatus.xcodeproj -scheme AgentStatus -destination 'platform=macOS' test

# Run one test class / one test
xcodebuild ... test -only-testing:AgentStatusTests/AgentCardModelTests
xcodebuild ... test -only-testing:AgentStatusTests/AgentCardModelTests/testIdleForShownAfterAMinute

scripts/perf-check.sh        # perf gate: PerfBenchmarks vs scripts/perf-baseline.txt (fails >2x)

scripts/verify.sh            # full pre-PR gate: xcodegen → build → test → perf → render snapshots
```

`/verify` (slash command) runs `scripts/verify.sh` then `/code-review` on the diff — the one-command way to close the dev loop below.

Launch for visual verification: `open build/Build/Products/Release/AgentStatus.app --args --commander` opens the fullscreen Commander board immediately (no menu-bar clicking). Kill a previous instance first (`pkill -x AgentStatus`) — only one instance reads the status items cleanly.

Headless UI snapshots (work even on a locked screen): `CardSnapshotRenderTests` and `DetailStripSnapshotRenderTests` render every card / detail-strip state via `ImageRenderer` to `/tmp/card-snapshots/` and `/tmp/strip-snapshots/` for eyeball review after UI changes.

## Dev loop

The repeatable cycle for changing this app. Gates marked `*` are **conditional** — run them only when the change touches that area (see the table). Cheap by default, thorough when it matters.

```
0. FRAME   Non-trivial change? → brainstorming → writing-plans. Feature/bugfix → TDD (test first).
1. CHANGE  Edit source. Added/removed a file? → edit project.yml, then `xcodegen generate`.
           Added a field a view reads? → add it to `EnrichedSession.coreEqual` + `EnrichedSessionCoreEqualTests`,
           or the UI silently won't update (see Architecture §3 and Gotchas).
2. BUILD   xcodebuild … build — fast compile check.
3. TEST    xcodebuild … test, iterating with `-only-testing:` on the class you touched.
4. PERF*   Touched Watching/ or transcript parsing? → scripts/perf-check.sh.
5. VISUAL* Touched UI/? → run the *SnapshotRenderTests, eyeball /tmp/*-snapshots/;
           launch --commander for interactive changes.
6. REVIEW  /code-review on the diff before PR.
7. SHIP    finishing-a-development-branch → commit + PR.
```

Which gates fire for what you touched:

| Touched | Build | Tests | Perf | Snapshots | Commander |
|---|---|---|---|---|---|
| `Model/`, `Store/` | ✓ | ✓ | — | — | — |
| `Watching/`, parsing (`ClaudeCode/`) | ✓ | ✓ | ✓ | — | — |
| `UI/` (any view) | ✓ | ✓ | — | ✓ | interactive changes |
| `App/`, `Util/`, `Providers/` plumbing | ✓ | ✓ | — | — | — |
| `project.yml` / file add or remove | ✓ (after `xcodegen generate`) | ✓ | — | — | — |
| Docs / comments only | — | — | — | — | — |

**Before any PR**, regardless of the table: run `scripts/verify.sh` (or `/verify`, which also runs `/code-review`).

## Architecture

Data flows one way: **provider → store → views**.

1. **Providers** (`AgentStatus/Providers/`): `SessionProvider` protocol — `start()`/`stop()` + an `AsyncStream<[SessionSnapshot]>`. `ClaudeCodeProvider` polls `~/.claude/sessions/*.json` (PID-liveness-checked via `kill(pid, 0)`) and attaches transcript-derived state. `CodexProvider` is a registered stub. New agent = one new file + `ProviderRegistry.register(...)`; everything downstream already handles multiple providers. Snapshot ids are namespaced `"<providerId>:<sessionId>"`.

2. **TranscriptTailer** (`AgentStatus/Watching/`): an actor per session that incrementally tails the JSONL transcript (byte-offset tracked, 1 MB chunks, 1 Hz poll) and folds each line into an `EnrichedSession` — active/recent tools, todo list, tokens/cost, context size, git branch, prompts. Every line is processed exactly once, so all accumulation (`tokens +=`, `estimatedCost +=`) relies on that idempotency. Cost is priced per-message at the model that produced it (sessions switch models). Sidechain (subagent) messages count toward tokens/cost only — never turns, contextTokens, currentModel, text, or tools. `contextTokens` is a gauge (replaced per top-level assistant message), not a meter.

3. **SessionStore** (`AgentStatus/Store/`): MainActor `ObservableObject`, single source of truth. Publishes `snapshots`/`aggregate` only when `uiEqual` says something visual changed — `EnrichedSession.coreEqual` gates UI republish, so **any new field a view reads must be added to `coreEqual`** (and to `EnrichedSessionCoreEqualTests`) or the UI silently won't update. Also owns per-session `HistoryBuffer`s for sparklines and a 5 s backup liveness ticker.

4. **UI** (`AgentStatus/UI/`): three surfaces sharing the same data — `MenuBar/` (aggregate icon + dropdown dashboard, per-session NSStatusItems), `PerSession/` (detail popover), `Commander/` (fullscreen board, opened via `CommanderWindowController` — imperative NSWindow, not a SwiftUI scene, so it's never auto-shown; app flips `.accessory` ↔ `.regular` as the window opens/closes). Commander cards group by urgency (`CommanderGroup`: Needs you / Working / Idle / Ended) and use a shared 1 Hz `TimelineView` tick — no per-card timers.

### View-model pattern

Display formatting lives in pure, `Equatable`, unit-tested builders, with views as thin renderers: `AgentCardModel.make(from:now:)` for Commander cards, `PerSessionStatusItem.rowData(from:now:)` for menu-bar rows. Put new display logic there (testable with a pinned `now`), not in view bodies.

### Test conventions

- Actors/stores expose underscored test hooks instead of widening their API: `TranscriptTailer._test_processLine`, `SessionStore._test_ingest`, `SessionStore._test_uiEqual`. Tests drive parsing by feeding synthesized JSONL strings — see `TranscriptParsingTests` helpers.
- Tests pin a fixed `now`; never compare against wall clock (tool durations use transcript timestamps for exactly this reason).
- `PerfBenchmarks` backs `scripts/perf-check.sh`; transcript parsing is the hot path (10k lines benchmarked), so keep per-line work cheap.

### Gotchas

- Swift 6 strict concurrency is on: model structs are `Sendable`; `ActiveTool.rawInputJSON` is `Data` (not `[String: Any]`) for this reason — decode at render time.
- `ISO8601DateFormatter` is built per call in the tailer (not `Sendable`); don't "optimize" it into a shared static.
- Claude Code transcript quirks the parser already handles (keep handling them): `tool_use` appears as both `Task` and `Agent` names; `TodoWrite` replaces the whole list while `TaskCreate`/`TaskUpdate` are incremental; `aiTitle` key (not `title`) on `ai-title` events; `gitBranch` is stamped on user/assistant/system records; `[1m]` suffix on model ids means a 1M context window (`ContextWindow.limit`).
- `LSUIElement` app: there is no Dock icon; windows must be opened via the controllers, and `NSApp.setActivationPolicy` transitions matter.
