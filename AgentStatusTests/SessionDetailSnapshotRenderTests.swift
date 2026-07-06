import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless renders of the redesigned per-session popover (`SessionDetailContent`)
/// — now led by the Commander `AgentCard` — to /tmp/detail-snapshots/*.png for
/// eyeball review. Synthetic data, no personal info.
@MainActor
final class SessionDetailSnapshotRenderTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let outDir = URL(fileURLWithPath: "/tmp/detail-snapshots", isDirectory: true)

    func testRenderDetailStates() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try render(name: "detail-busy", snap: busySnap())
        try render(name: "detail-waiting", snap: waitingSnap())
        try render(name: "detail-error", snap: errorSnap())
        try render(name: "detail-idle-goal", snap: goalAchievedSnap())
    }

    private func render(name: String, snap: SessionSnapshot) throws {
        let store = SessionStore(registry: ProviderRegistry())
        store._test_ingest(providerId: snap.providerId, snapshots: [snap])
        seedHistory(store.history(for: snap.id))

        let view = SessionDetailContent(snapshotId: snap.id, now: t0)
            .frame(width: 380)
            .environmentObject(store)
            .environmentObject(Settings())
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.07, green: 0.08, blue: 0.10))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return XCTFail("no image for \(name)") }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG encode failed for \(name)")
        }
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 5_000)
    }

    private func seedHistory(_ buf: HistoryBuffer) {
        var total = 800_000.0
        for k in 0..<60 {
            total += Double((k % 5) * 40_000)
            buf.append(SessionHistorySample(timestamp: t0.addingTimeInterval(Double(-60 + k)),
                                            status: .busy, tokens: Int(total)))
        }
    }

    // MARK: - Fixtures

    private func base(_ status: SessionStatus, isAlive: Bool = true, updatedAt: TimeInterval = -60,
                      waitingFor: String? = nil, enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "p:detail", providerId: "p", pid: 4242, sessionId: "detail",
            cwd: URL(fileURLWithPath: "/Users/dev/code/payments-service"),
            startedAt: t0.addingTimeInterval(-4_560), updatedAt: t0.addingTimeInterval(updatedAt),
            status: status, waitingFor: waitingFor, version: "2.1.170", kind: "interactive",
            entrypoint: "cli", isAlive: isAlive, enriched: enriched
        )
    }

    private func common() -> EnrichedSession {
        var e = EnrichedSession.empty
        e.aiTitle = "Refactor payment retry queue"
        e.currentModel = "claude-opus-4-8"
        e.permissionMode = "acceptEdits"
        e.gitBranch = "feature/retry-backoff"
        e.tokens = TokenUsage(input: 42_000, output: 96_000, cacheRead: 14_800_000, cacheCreation: 410_000)
        e.estimatedCost = 9.84
        e.contextTokens = 147_000
        e.assistantTurns = 61
        e.toolCalls = 118
        e.lastUserPrompt = "Refactor the retry queue to use exponential backoff"
        e.lastAssistantText = "Mapped three call sites; switching the queue to exponential backoff with jitter now."
        e.todos = [
            TodoItem(id: "1", title: "Map current retry call sites", activeForm: nil, status: .completed),
            TodoItem(id: "2", title: "Pick backoff strategy", activeForm: "Picking backoff strategy", status: .inProgress),
            TodoItem(id: "3", title: "Implement queue changes", activeForm: nil, status: .pending),
        ]
        return e
    }

    private func busySnap() -> SessionSnapshot {
        var e = common()
        e.activeTools = [
            ActiveTool(id: "t1", name: "Bash", preview: "xcodebuild -scheme AgentStatus test",
                       startedAt: t0.addingTimeInterval(-47)),
            ActiveTool(id: "t2", name: "Read", preview: "queue.ts", startedAt: t0.addingTimeInterval(-20)),
        ]
        return base(.busy, enriched: e)
    }

    private func waitingSnap() -> SessionSnapshot {
        var e = common()
        e.activeTools = [ActiveTool(id: "q", name: "Bash", preview: "rm -rf build",
                                    startedAt: t0.addingTimeInterval(-30))]
        return base(.waiting, waitingFor: "permission prompt", enriched: e)
    }

    private func errorSnap() -> SessionSnapshot {
        var e = common()
        e.currentModel = "claude-sonnet-4-6"
        e.permissionMode = "bypassPermissions"
        e.contextTokens = 188_000
        e.errorCount = 1
        let failed = ActiveTool(id: "e", name: "Bash", preview: "python backfill.py",
                                startedAt: t0.addingTimeInterval(-700))
        e.recentTools = [CompletedTool(completing: failed, isError: true, at: t0.addingTimeInterval(-660))]
        return base(.error, updatedAt: -660, enriched: e)
    }

    private func goalAchievedSnap() -> SessionSnapshot {
        var e = common()
        e.goalCondition = "all integration tests green on CI"
        e.goalOutcome = GoalOutcome(durationMs: 728_241, iterations: 1, tokens: 53_203)
        e.contextTokens = 128_000
        return base(.idle, updatedAt: -455, enriched: e)
    }
}
