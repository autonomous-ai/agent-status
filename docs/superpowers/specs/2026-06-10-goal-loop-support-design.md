# Goal & Loop Support — Design

**Date:** 2026-06-10
**Status:** Approved (decisions delegated to implementer)

## Problem

When an engineer watches a board of Claude Code agents, the single most
load-bearing missing fact is *which sessions are running autonomously*. A
session can be put under a `/goal` Stop-hook (it keeps re-prompting itself until
a condition holds) or into a `/loop` (it re-runs a prompt on an interval or
self-paces). Such a session that *looks* idle is **not** done — the harness will
wake it again. Today the app shows nothing about this, so an engineer can
misread an autonomous session as finished.

## Goal

Detect and surface, per session:

- **Goal** (full support): the active `/goal` condition text.
- **Loop** (best-effort): that the session was put into `/loop` mode, and its
  target.

## On-disk signals (verified against real transcripts)

- **Goal set** — a `user` record whose text contains
  `<local-command-stdout>Goal set: <condition></local-command-stdout>`.
  Confirmed present in multiple transcripts. Fallback: the meta user message
  `A session-scoped Stop hook is now active with condition: "<condition>".`
- **Goal clear** — no occurrence exists in any current transcript (nobody has
  cleared one). Auto-clear when the condition is met leaves **no** on-disk
  trace. Handled defensively: a `/goal` command whose `<command-args>` is
  `clear`, or a `Goal cleared` stdout, resets the condition.
- **Loop** — no `/loop` occurrence exists in any current transcript, confirming
  loop must be best-effort. Detectable signal: a `user` record containing
  `<command-name>/loop</command-name>` plus its `<command-args>`.

### Known limitations (documented, accepted)

- A goal that auto-clears on completion leaves no trace, so `goalCondition` can
  persist as **stale** until the session ends or the user clears it. We surface
  it honestly as "this session was put under a goal"; we do not claim live
  completion tracking.
- Loop *stop* is not reliably detectable. The loop chip means "put into loop
  mode"; it clears only on `/clear` or session end.

Because both signals can go stale, they drive **display only** — never status
classification or grouping. Letting possibly-stale data move a card between
"Working"/"Idle" groups would erode trust. A clearly-labeled chip is honest;
a reclassification is not.

## Design

Data flows the existing one way: provider → store → views.

### 1. Detection — `TranscriptTailer`

In the `user`-message path, scan the message text for the signals above:

- `Goal set: X` (stdout) or the stop-hook meta line → `state.goalCondition = X`.
- `/goal` + `clear` args, or `Goal cleared` stdout → `state.goalCondition = nil`.
- `<command-name>/loop</command-name>` → `state.loopTarget =` trimmed
  `<command-args>`, or `"self-paced"` when args are empty.

Keep per-line work cheap (it's the hot path): cheap `contains` guards before any
substring extraction. Extraction helpers are pure static functions, unit-tested.

### 2. Model — `EnrichedSession`

Add:

```swift
var goalCondition: String? = nil   // active /goal condition, nil if none/cleared
var loopTarget: String? = nil      // /loop target, nil if not looping
```

Both MUST be added to `coreEqual` (and `EnrichedSessionCoreEqualTests`) or the
UI will silently not republish when they change.

### 3. View-models (pure, `Equatable`, unit-tested)

- `AgentCardModel.make(from:now:)` — add `goal: String?` and `loop: String?`;
  rendered as chips in the card's existing chip row.
- `PerSessionStatusItem.rowData(from:now:)` — add a compact `🎯`/`🔁` glyph plus
  truncated text for menu-bar rows.

### 4. Surfaces

All three shared-data surfaces:

- **Commander cards** (primary): full goal/loop chips.
- **Per-session popover** (`SessionDetailView`): full goal condition / loop
  target text.
- **Menu-bar dashboard rows**: compact glyph + truncated text.

### 5. Tests

- `TranscriptParsingTests`: goal-set (stdout + meta fallback), goal-clear, loop
  detection, and that a non-goal stdout does not set a goal.
- `EnrichedSessionCoreEqualTests`: republish on `goalCondition` / `loopTarget`
  change.
- `AgentCardModelTests` + `PerSessionRowDataTests`: chip / glyph rendering.
- Snapshot tests (`CardSnapshotRenderTests`, etc.) pick up the new visual states
  automatically.

## Out of scope

- Live goal-completion / loop-stop detection (no reliable signal).
- Notifications on goal completion.
- Status/grouping changes driven by goal/loop.
