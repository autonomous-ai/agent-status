import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless renders of `CommanderDetailStrip` (the inline expansion panel) to
/// /tmp/strip-snapshots/*.png — same eyeball-verification approach as
/// `CardSnapshotRenderTests`, at full board width.
@MainActor
final class DetailStripSnapshotRenderTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let outDir = URL(fileURLWithPath: "/tmp/strip-snapshots", isDirectory: true)

    func testRenderDetailStripStates() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try render(name: "strip-waiting", snap: waitingSnap())
        try render(name: "strip-error", snap: errorSnap())
    }

    private func render(name: String, snap: SessionSnapshot) throws {
        let store = SessionStore(registry: ProviderRegistry())
        store._test_ingest(providerId: snap.providerId, snapshots: [snap])

        let strip = CommanderDetailStrip(snapshotId: snap.id, now: t0)
            .environmentObject(store)
            .environmentObject(Settings())
            .frame(width: 1232)
            .padding(24)
            .background(Color(red: 0.06, green: 0.07, blue: 0.09))
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            return XCTFail("ImageRenderer produced no image for \(name)")
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG encode failed for \(name)")
        }
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 1_000)
    }

    // MARK: - Fixtures

    private func base(_ status: SessionStatus, waitingFor: String? = nil,
                      enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "p:strip", providerId: "p", pid: 4242, sessionId: "strip",
            cwd: URL(fileURLWithPath: "/Users/dee/repos/payments"),
            startedAt: t0.addingTimeInterval(-4_560),
            updatedAt: t0.addingTimeInterval(-90),
            status: status, waitingFor: waitingFor,
            version: "2.1.170", kind: "interactive", entrypoint: "cli",
            isAlive: true, enriched: enriched
        )
    }

    private func waitingSnap() -> SessionSnapshot {
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
        e.lastUserPrompt = "Refactor the retry queue to use exponential backoff"
        e.lastAssistantText = "I found three call sites. Before I restructure the queue, which backoff strategy do you prefer?"
        let questionInput: [String: Any] = ["questions": [[
            "question": "Which backoff strategy should the retry queue use?",
            "options": [["label": "Exponential with jitter (recommended)"],
                        ["label": "Fixed 30s intervals"],
                        ["label": "Fibonacci backoff"]],
        ]]]
        e.activeTools = [ActiveTool(
            id: "q1", name: "AskUserQuestion", preview: "",
            startedAt: t0.addingTimeInterval(-46),
            rawInputJSON: try? JSONSerialization.data(withJSONObject: questionInput))]
        e.todos = [
            TodoItem(id: "1", title: "Map current retry call sites", activeForm: nil, status: .completed),
            TodoItem(id: "2", title: "Pick backoff strategy", activeForm: "Picking backoff strategy", status: .inProgress),
            TodoItem(id: "3", title: "Implement queue changes", activeForm: nil, status: .pending),
        ]
        return base(.waiting, waitingFor: "permission prompt", enriched: e)
    }

    /// Mirrors the live repro that looked like a missing third column: a session
    /// with tokens but no task list and a single failed tool.
    private func errorSnap() -> SessionSnapshot {
        var e = EnrichedSession.empty
        e.aiTitle = "Backfill analytics events"
        e.currentModel = "claude-sonnet-4-6"
        e.gitBranch = "main"
        e.tokens = TokenUsage(input: 3_000, output: 1_200, cacheRead: 176_000, cacheCreation: 8_000)
        e.estimatedCost = 0.11
        e.contextTokens = 187_000
        e.assistantTurns = 1
        e.toolCalls = 1
        e.errorCount = 1
        e.lastUserPrompt = "Backfill the missing analytics events from March"
        let failed = ActiveTool(id: "e1", name: "Bash",
                                preview: "python backfill.py --from 2026-03-01",
                                startedAt: t0.addingTimeInterval(-700))
        e.recentTools = [CompletedTool(completing: failed, isError: true,
                                       at: t0.addingTimeInterval(-660))]
        return base(.error, enriched: e)
    }
}
