import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless render of the whole `CommanderView` board — a marketing/README hero
/// shot built entirely from synthetic sessions, so it carries NO personal info
/// (no real cwd, spend, branch, or desktop chrome). Writes
/// /tmp/board-snapshots/commander-board.png via `ImageRenderer` (no window, no
/// screen recording). Covers every `CommanderGroup`: Needs you / Working / Idle
/// / Ended, with a spread of card states in each.
///
/// Timestamps are anchored to the real wall clock (`now = Date()`) on purpose:
/// the live board's `TimelineView` reads the real clock, so fixtures must too or
/// every elapsed/duration label renders as a huge bogus span.
@MainActor
final class CommanderBoardSnapshotRenderTests: XCTestCase {

    private let now = Date()
    private let outDir = URL(fileURLWithPath: "/tmp/board-snapshots", isDirectory: true)

    func testRenderCommanderBoard() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let snaps = demoSessions()
        let store = SessionStore(registry: ProviderRegistry())
        store._test_ingest(providerId: "demo", snapshots: snaps)
        // Seed each live session's history so the spend sparklines have shape
        // (a rising 60-bucket curve ending at `now`).
        for (i, s) in snaps.enumerated() where s.isAlive {
            seedHistory(store.history(for: s.id), seed: i)
        }

        let board = CommanderView(staticLayout: true, staticColumns: 3)
            .environmentObject(store)
            .environmentObject(Settings())
            .frame(width: 1440)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            return XCTFail("ImageRenderer produced no image for the board")
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG encode failed for the board")
        }
        try png.write(to: outDir.appendingPathComponent("commander-board.png"))
        XCTAssertGreaterThan(png.count, 10_000, "board png suspiciously small")
    }

    // MARK: - History plumbing

    /// A rising cumulative token curve, offset per card so no two sparklines
    /// look identical.
    private func seedHistory(_ buf: HistoryBuffer, seed: Int) {
        var total = Double(300_000 + seed * 120_000)
        for k in 0..<60 {
            let ts = now.addingTimeInterval(Double(-60 + k))
            total += Double(((k + seed) % 6) * 30_000)
            buf.append(SessionHistorySample(timestamp: ts, status: .busy, tokens: Int(total)))
        }
    }

    // MARK: - Synthetic session set (clean, no personal info)

    private func demoSessions() -> [SessionSnapshot] {
        [
            waitingSnap(), errorSnap(),                      // Needs you
            busyMultiSnap(), thinkingSnap(), goalLoopSnap(), // Working
            idleSnap(), goalAchievedSnap(),                  // Idle
            endedSnap(),                                     // Ended
        ]
    }

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func base(id: String, project: String, status: SessionStatus,
                      isAlive: Bool = true, startedAgo: TimeInterval = 5_400,
                      updatedAgo: TimeInterval = 40,
                      waitingFor: String? = nil, enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "demo:\(id)", providerId: "demo", pid: pid_t(4000 + abs(id.hashValue % 900)),
            sessionId: id,
            cwd: URL(fileURLWithPath: "/Users/dev/code/\(project)"),
            startedAt: ago(startedAgo),
            updatedAt: ago(updatedAgo),
            status: status, waitingFor: waitingFor,
            version: "2.1.170", kind: "interactive", entrypoint: "cli",
            isAlive: isAlive, enriched: enriched
        )
    }

    private func enriched(title: String, model: String, mode: String, branch: String,
                          tokens: TokenUsage, costUSD: Double, contextTokens: Int,
                          turns: Int, tools: Int, todos: [TodoItem] = []) -> EnrichedSession {
        var e = EnrichedSession.empty
        e.aiTitle = title
        e.currentModel = model
        e.permissionMode = mode
        e.gitBranch = branch
        e.tokens = tokens
        e.estimatedCost = costUSD
        e.contextTokens = contextTokens
        e.assistantTurns = turns
        e.toolCalls = tools
        e.todos = todos
        return e
    }

    /// Cache-heavy token mix (as real Claude Code sessions run) totalling ~`M`
    /// million tokens, so each card shows a distinct headline figure.
    private func tokens(totalM: Double) -> TokenUsage {
        let cacheRead = Int(totalM * 1_000_000) - 122_000 - 360_000
        return TokenUsage(input: 38_000, output: 84_000,
                          cacheRead: max(0, cacheRead), cacheCreation: 360_000)
    }

    private func sampleTodos() -> [TodoItem] {
        [
            TodoItem(id: "1", title: "Map current call sites", activeForm: nil, status: .completed),
            TodoItem(id: "2", title: "Pick a strategy", activeForm: "Picking a strategy", status: .inProgress),
            TodoItem(id: "3", title: "Implement the change", activeForm: nil, status: .pending),
            TodoItem(id: "4", title: "Add tests", activeForm: nil, status: .pending),
        ]
    }

    // Needs you --------------------------------------------------------------

    private func waitingSnap() -> SessionSnapshot {
        var e = enriched(title: "Add OAuth token refresh", model: "claude-opus-4-8",
                         mode: "plan", branch: "feature/oauth-refresh",
                         tokens: tokens(totalM: 8.7), costUSD: 6.20, contextTokens: 141_000,
                         turns: 44, tools: 71, todos: sampleTodos())
        e.activeTools = [ActiveTool(id: "q1", name: "AskUserQuestion", preview: "",
                                    startedAt: ago(38))]
        return base(id: "auth", project: "auth-service", status: .waiting,
                    startedAgo: 5_520, updatedAgo: 38, waitingFor: "your answer", enriched: e)
    }

    private func errorSnap() -> SessionSnapshot {
        var e = enriched(title: "Backfill analytics events", model: "claude-sonnet-4-6",
                         mode: "bypassPermissions", branch: "main",
                         tokens: tokens(totalM: 0.6), costUSD: 0.34, contextTokens: 188_000,
                         turns: 3, tools: 5)
        e.errorCount = 1
        let failed = ActiveTool(id: "e1", name: "Bash", preview: "python backfill.py --from march",
                                startedAt: ago(720))
        e.recentTools = [CompletedTool(completing: failed, isError: true, at: ago(680))]
        return base(id: "etl", project: "analytics-etl", status: .error,
                    startedAgo: 840, updatedAgo: 680, enriched: e)
    }

    // Working ----------------------------------------------------------------

    private func busyMultiSnap() -> SessionSnapshot {
        var e = enriched(title: "Refactor payment retry queue", model: "claude-opus-4-8",
                         mode: "acceptEdits", branch: "feature/retry-backoff",
                         tokens: tokens(totalM: 15.3), costUSD: 9.84, contextTokens: 147_000,
                         turns: 61, tools: 118, todos: sampleTodos())
        e.activeTools = [
            ActiveTool(id: "t1", name: "Bash", preview: "npm run build", startedAt: ago(29)),
            ActiveTool(id: "t2", name: "Read", preview: "queue.ts", startedAt: ago(19)),
            ActiveTool(id: "t3", name: "Agent", preview: "audit retry paths", startedAt: ago(11)),
        ]
        return base(id: "pay", project: "payments-service", status: .busy,
                    startedAgo: 4_680, updatedAgo: 11, enriched: e)
    }

    private func thinkingSnap() -> SessionSnapshot {
        var e = enriched(title: "Migrate to Postgres 16", model: "claude-opus-4-8",
                         mode: "acceptEdits", branch: "chore/pg16",
                         tokens: tokens(totalM: 6.6), costUSD: 4.05, contextTokens: 96_000,
                         turns: 28, tools: 52, todos: sampleTodos())
        let edited = ActiveTool(id: "t9", name: "Edit", preview: "migrations/0042_pg16.sql",
                                startedAt: ago(88))
        e.recentTools = [CompletedTool(completing: edited, isError: false, at: ago(64))]
        return base(id: "core", project: "core-api", status: .busy,
                    startedAgo: 2_760, updatedAgo: 64, enriched: e)
    }

    private func goalLoopSnap() -> SessionSnapshot {
        var e = enriched(title: "Green the CI board", model: "claude-opus-4-8",
                         mode: "bypassPermissions", branch: "ci/flaky-fixes",
                         tokens: tokens(totalM: 22.4), costUSD: 12.60, contextTokens: 118_000,
                         turns: 90, tools: 205)
        e.goalCondition = "all integration tests green on CI"
        e.loopTarget = "10m /babysit-prs"
        e.activeTools = [ActiveTool(id: "t1", name: "Bash", preview: "gh pr checks",
                                    startedAt: ago(9))]
        return base(id: "store", project: "web-storefront", status: .busy,
                    startedAgo: 11_520, updatedAgo: 9, enriched: e)
    }

    // Idle -------------------------------------------------------------------

    private func idleSnap() -> SessionSnapshot {
        let e = enriched(title: "Write API integration tests", model: "claude-opus-4-8",
                         mode: "plan", branch: "test/api-integration",
                         tokens: tokens(totalM: 3.9), costUSD: 2.10, contextTokens: 52_000,
                         turns: 17, tools: 33, todos: sampleTodos())
        return base(id: "gw", project: "api-gateway", status: .idle,
                    startedAgo: 3_840, updatedAgo: 1_140, enriched: e)
    }

    private func goalAchievedSnap() -> SessionSnapshot {
        var e = enriched(title: "Design plugin protocol", model: "claude-opus-4-8",
                         mode: "plan", branch: "feature/plugin-protocol",
                         tokens: tokens(totalM: 9.5), costUSD: 3.72, contextTokens: 128_000,
                         turns: 40, tools: 60)
        e.goalCondition = "an open protocol the community can build adapters against"
        e.goalOutcome = GoalOutcome(durationMs: 728_241, iterations: 1, tokens: 53_203)
        return base(id: "sdk", project: "sdk-core", status: .idle,
                    startedAgo: 3_120, updatedAgo: 420, enriched: e)
    }

    // Ended ------------------------------------------------------------------

    private func endedSnap() -> SessionSnapshot {
        let e = enriched(title: "Update onboarding docs", model: "claude-opus-4-8",
                         mode: "acceptEdits", branch: "docs/onboarding",
                         tokens: tokens(totalM: 2.0), costUSD: 1.18, contextTokens: 41_000,
                         turns: 12, tools: 20)
        return base(id: "docs", project: "docs-site", status: .stopped,
                    isAlive: false, startedAgo: 18_000, updatedAgo: 7_200, enriched: e)
    }
}
