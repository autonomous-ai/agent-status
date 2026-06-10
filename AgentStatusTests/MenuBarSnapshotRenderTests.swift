import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless renders of the menu-bar dashboard popover surfaces — `DashboardView`
/// (header + SessionRow list) and `SessionDetailView` (per-session popover) — to
/// /tmp/menubar-snapshots/*.png via `ImageRenderer`. Same eyeball-verification
/// approach as the Commander snapshot tests; works on a locked screen.
@MainActor
final class MenuBarSnapshotRenderTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let outDir = URL(fileURLWithPath: "/tmp/menubar-snapshots", isDirectory: true)

    func testRenderSessionRows() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        // Individual rows with a pinned `now` (DashboardView owns the TimelineView
        // in production; ImageRenderer can't drive a TimelineView, so we render
        // the pure row directly — same split as the Commander AgentCard test).
        try renderRow(name: "row-busy", snap: busySnap())
        try renderRow(name: "row-waiting", snap: waitingSnap())
        try renderRow(name: "row-error", snap: errorSnap())
        try renderRow(name: "row-idle", snap: idleSnap())

        // A four-row stack approximating the popover list (header/footer use
        // SF Symbols ImageRenderer can't load, so we render the list body).
        let now = t0
        let rows = VStack(spacing: 0) {
            ForEach([busySnap(), waitingSnap(), errorSnap(), idleSnap()]) { snap in
                SessionRow(snapshot: snap,
                           model: AgentCardModel.make(from: snap, now: now),
                           buckets: self.demoBuckets(snap.status))
                    .environmentObject(Settings())
                Divider().padding(.leading, 44)
            }
        }
        .frame(width: 380)
        try render(name: "row-list", view: rows)
    }

    private func renderRow(name: String, snap: SessionSnapshot) throws {
        let row = SessionRow(snapshot: snap,
                             model: AgentCardModel.make(from: snap, now: t0),
                             buckets: demoBuckets(snap.status))
            .environmentObject(Settings())
            .frame(width: 380)
        try render(name: name, view: row)
    }

    private func demoBuckets(_ status: SessionStatus) -> [SessionStatus?] {
        (0..<60).map { i in i % 5 == 0 ? nil : status }
    }

    private func render<V: View>(name: String, view: V) throws {
        let wrapped = view
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        let renderer = ImageRenderer(content: wrapped)
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

    // MARK: - Fixtures

    private func base(_ status: SessionStatus, id: String, title: String,
                      isAlive: Bool = true, updatedAt: TimeInterval = -90,
                      waitingFor: String? = nil, enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "claude-code:\(id)", providerId: "claude-code", pid: 4242, sessionId: id,
            cwd: URL(fileURLWithPath: "/Users/dee/repos/\(title)"),
            startedAt: t0.addingTimeInterval(-4_560),
            updatedAt: t0.addingTimeInterval(updatedAt),
            status: status, waitingFor: waitingFor,
            version: "2.1.170", kind: "interactive", entrypoint: "cli",
            isAlive: isAlive, enriched: enriched
        )
    }

    private func enriched(title: String, model: String, mode: String, branch: String,
                          context: Int, cost: Double) -> EnrichedSession {
        var e = EnrichedSession.empty
        e.aiTitle = title
        e.currentModel = model
        e.permissionMode = mode
        e.gitBranch = branch
        e.tokens = TokenUsage(input: 42_000, output: 96_000, cacheRead: 4_800_000, cacheCreation: 210_000)
        e.estimatedCost = cost
        e.contextTokens = context
        e.assistantTurns = 41
        e.toolCalls = 88
        e.lastUserPrompt = "Refactor the retry queue to use exponential backoff"
        e.todos = [
            TodoItem(id: "1", title: "Map call sites", activeForm: nil, status: .completed),
            TodoItem(id: "2", title: "Pick strategy", activeForm: "Picking strategy", status: .inProgress),
            TodoItem(id: "3", title: "Implement", activeForm: nil, status: .pending),
        ]
        return e
    }

    private func busySnap() -> SessionSnapshot {
        var e = enriched(title: "Refactor payment retry queue", model: "claude-opus-4-8", mode: "plan",
                         branch: "feature/retry-backoff", context: 147_000, cost: 9.84)
        e.activeTools = [ActiveTool(id: "t1", name: "Bash",
                                    preview: "xcodebuild -scheme AgentStatus test",
                                    startedAt: t0.addingTimeInterval(-47))]
        return base(.busy, id: "busy", title: "payments", enriched: e)
    }

    private func waitingSnap() -> SessionSnapshot {
        var e = enriched(title: "ingest", model: "claude-opus-4-8", mode: "default",
                         branch: "main", context: 88_000, cost: 2.10)
        e.activeTools = [ActiveTool(id: "t2", name: "Bash", preview: "rm -rf build",
                                    startedAt: t0.addingTimeInterval(-12))]
        return base(.waiting, id: "wait", title: "ingest",
                    waitingFor: "permission prompt", enriched: e)
    }

    private func errorSnap() -> SessionSnapshot {
        var e = enriched(title: "analytics", model: "claude-sonnet-4-6", mode: "bypassPermissions",
                         branch: "main", context: 187_000, cost: 0.42)
        let failed = ActiveTool(id: "e1", name: "Bash", preview: "python backfill.py",
                                startedAt: t0.addingTimeInterval(-700))
        e.recentTools = [CompletedTool(completing: failed, isError: true,
                                       at: t0.addingTimeInterval(-660))]
        return base(.error, id: "err", title: "analytics", updatedAt: -660, enriched: e)
    }

    private func idleSnap() -> SessionSnapshot {
        let e = enriched(title: "docs", model: "claude-haiku-4-5", mode: "default",
                         branch: "docs/readme", context: 32_000, cost: 0.08)
        return base(.idle, id: "idle", title: "docs", updatedAt: -900, enriched: e)
    }
}
