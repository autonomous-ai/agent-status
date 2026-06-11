import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless pixel checks: renders `AgentCard` in each visual state to PNGs under
/// /tmp/card-snapshots/ via `ImageRenderer` (no window, no screen recording —
/// works even on a locked machine). Not an assertion-based snapshot diff; the
/// PNGs exist so a human (or agent) can eyeball every card state after UI work.
@MainActor
final class CardSnapshotRenderTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let outDir = URL(fileURLWithPath: "/tmp/card-snapshots", isDirectory: true)

    func testRenderAllCardStates() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        try render(name: "busy-single-tool", snap: busySnap())
        try render(name: "busy-multi-tool", snap: busyMultiSnap())
        try render(name: "thinking", snap: thinkingSnap())
        try render(name: "waiting-question", snap: waitingSnap())
        try render(name: "error-stuck", snap: errorSnap())
        try render(name: "idle-resting", snap: idleSnap())
        try render(name: "goal-loop", snap: autonomousSnap())
        try render(name: "goal-achieved", snap: goalAchievedSnap())
        try render(name: "ended", snap: endedSnap(), spend: [])
    }

    // MARK: - Render plumbing

    private func render(name: String, snap: SessionSnapshot,
                        spend: [Double?]? = nil) throws {
        let model = AgentCardModel.make(from: snap, now: t0)
        let card = AgentCard(
            model: model,
            spend: spend ?? demoSpend(),
            isSelected: false,
            onTap: {}
        )
        .environmentObject(Settings())
        .frame(width: 400)
        .padding(24)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            return XCTFail("ImageRenderer produced no image for \(name)")
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG encode failed for \(name)")
        }
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 1_000, "\(name).png suspiciously small")
    }

    /// A plausible 60-bucket cumulative token curve for the spend sparkline —
    /// climbing with a few flat stretches, so the rendered chart has shape.
    private func demoSpend() -> [Double?] {
        var total = 1_200_000.0
        return (0..<60).map { i in
            total += Double((i % 5) * 40_000)   // bursty growth
            return total
        }
    }

    // MARK: - Fixtures (one per visual state)

    private func base(_ status: SessionStatus, isAlive: Bool = true,
                      updatedAt: TimeInterval = -90, waitingFor: String? = nil,
                      enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "p:snapshot", providerId: "p", pid: 4242, sessionId: "snapshot",
            cwd: URL(fileURLWithPath: "/Users/dee/repos/payments"),
            startedAt: t0.addingTimeInterval(-4_560),
            updatedAt: t0.addingTimeInterval(updatedAt),
            status: status, waitingFor: waitingFor,
            version: "2.1.170", kind: "interactive", entrypoint: "cli",
            isAlive: isAlive, enriched: enriched
        )
    }

    private func commonEnriched() -> EnrichedSession {
        var e = EnrichedSession.empty
        e.aiTitle = "Refactor payment retry queue"
        e.currentModel = "claude-opus-4-8"
        e.permissionMode = "plan"
        e.gitBranch = "feature/retry-backoff"
        e.tokens = TokenUsage(input: 42_000, output: 96_000, cacheRead: 14_800_000, cacheCreation: 410_000)
        e.estimatedCost = 9.84
        e.contextTokens = 147_000
        e.assistantTurns = 61
        e.toolCalls = 118
        e.todos = [
            TodoItem(id: "1", title: "Map current retry call sites", activeForm: nil, status: .completed),
            TodoItem(id: "2", title: "Pick backoff strategy", activeForm: "Picking backoff strategy", status: .inProgress),
            TodoItem(id: "3", title: "Implement queue changes", activeForm: nil, status: .pending),
            TodoItem(id: "4", title: "Add jitter tests", activeForm: nil, status: .pending),
        ]
        return e
    }

    private func busySnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.activeTools = [ActiveTool(id: "t1", name: "Bash",
                                    preview: "xcodebuild -scheme AgentStatus test",
                                    startedAt: t0.addingTimeInterval(-47))]
        return base(.busy, enriched: e)
    }

    private func busyMultiSnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.activeTools = [
            ActiveTool(id: "t1", name: "Bash", preview: "npm run build",
                       startedAt: t0.addingTimeInterval(-31)),
            ActiveTool(id: "t2", name: "Read", preview: "queue.ts",
                       startedAt: t0.addingTimeInterval(-22)),
            ActiveTool(id: "t3", name: "Agent", preview: "audit retry paths",
                       startedAt: t0.addingTimeInterval(-15)),
        ]
        return base(.busy, enriched: e)
    }

    private func thinkingSnap() -> SessionSnapshot {
        var e = commonEnriched()
        // Generating with no tool in flight, but it just finished an Edit — the
        // card should read "just Edit · queue.ts · <timer>", not a bare "Thinking…".
        let edited = ActiveTool(id: "t9", name: "Edit", preview: "queue.ts",
                                startedAt: t0.addingTimeInterval(-95), rawInputJSON: nil)
        e.recentTools = [CompletedTool(completing: edited, isError: false,
                                       at: t0.addingTimeInterval(-72))]
        return base(.busy, enriched: e)
    }

    private func waitingSnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.activeTools = [ActiveTool(id: "t2", name: "AskUserQuestion", preview: "",
                                    startedAt: t0.addingTimeInterval(-46))]
        return base(.waiting, waitingFor: "permission prompt", enriched: e)
    }

    private func errorSnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.currentModel = "claude-sonnet-4-6"
        e.permissionMode = "bypassPermissions"
        e.contextTokens = 187_000
        e.errorCount = 1
        let failed = ActiveTool(id: "t3", name: "Bash", preview: "python backfill.py",
                                startedAt: t0.addingTimeInterval(-700))
        e.recentTools = [CompletedTool(completing: failed, isError: true,
                                       at: t0.addingTimeInterval(-660))]
        return base(.error, updatedAt: -660, enriched: e)
    }

    private func idleSnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.contextTokens = 52_000
        return base(.idle, updatedAt: -1_080, enriched: e)
    }

    private func autonomousSnap() -> SessionSnapshot {
        var e = commonEnriched()
        e.goalCondition = "all integration tests green on CI"
        e.loopTarget = "10m /babysit-prs"
        e.activeTools = [ActiveTool(id: "t1", name: "Bash", preview: "gh pr checks",
                                    startedAt: t0.addingTimeInterval(-12))]
        return base(.busy, enriched: e)
    }

    private func goalAchievedSnap() -> SessionSnapshot {
        // The scenario from the report: a /goal session that's done and resting —
        // the banner must read green "Goal achieved", not a stale pink "pursuing".
        var e = commonEnriched()
        e.goalCondition = "design a protocol/open standard so the community can build adapters"
        e.goalOutcome = GoalOutcome(durationMs: 728_241, iterations: 1, tokens: 53_203)
        e.contextTokens = 128_000
        return base(.idle, updatedAt: -455, enriched: e)
    }

    private func endedSnap() -> SessionSnapshot {
        base(.stopped, isAlive: false, updatedAt: -7_200, enriched: commonEnriched())
    }
}
