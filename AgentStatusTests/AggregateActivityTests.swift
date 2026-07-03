import XCTest
@testable import AgentStatus

/// Unit tests for the menu-bar activity view-model. Pins `now` so elapsed is
/// deterministic; drives the builder with synthesized snapshots.
final class AggregateActivityTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func snap(_ status: SessionStatus, pid: Int32 = 1, alive: Bool = true,
                      updatedAt: Date? = nil, enriched: EnrichedSession? = nil) -> SessionSnapshot {
        SessionSnapshot(
            id: "p:\(pid)", providerId: "p", pid: pid, sessionId: "\(pid)",
            cwd: URL(fileURLWithPath: "/tmp"), startedAt: t0, updatedAt: updatedAt ?? t0,
            status: status, waitingFor: nil, version: nil, kind: "interactive",
            entrypoint: "cli", isAlive: alive, enriched: enriched
        )
    }

    private func busyWithTool(name: String, preview: String, startedAt: Date,
                              pid: Int32 = 1, updatedAt: Date? = nil,
                              title: String? = nil) -> SessionSnapshot {
        var e = EnrichedSession.empty
        if let title { e.aiTitle = title }
        e.activeTools = [ActiveTool(id: "t\(pid)", name: name, preview: preview, startedAt: startedAt)]
        return snap(.busy, pid: pid, updatedAt: updatedAt, enriched: e)
    }

    // MARK: - Empty / idle

    func testEmptyWhenNoLiveSessions() {
        let a = AggregateActivity.make(from: [], now: t0)
        XCTAssertEqual(a.mode, .empty)
        XCTAssertEqual(a.text, "")
        XCTAssertNil(a.badge)
        XCTAssertFalse(a.urgent)
    }

    func testDeadSessionsAreIgnored() {
        let a = AggregateActivity.make(from: [snap(.busy, alive: false)], now: t0)
        XCTAssertEqual(a.mode, .empty)
    }

    func testIdleShowsLiveCount() {
        let a = AggregateActivity.make(from: [
            snap(.idle, pid: 1), snap(.idle, pid: 2), snap(.stopped, pid: 3, alive: true),
        ], now: t0)
        XCTAssertEqual(a.mode, .idle)
        XCTAssertEqual(a.iconStatus, .idle)
        XCTAssertEqual(a.badge, "3")
        XCTAssertEqual(a.text, "")
        XCTAssertFalse(a.urgent)
    }

    // MARK: - Working

    func testWorkingSingleShowsToolAndPreview() {
        let s = busyWithTool(name: "Bash", preview: "xcodebuild test", startedAt: t0.addingTimeInterval(-10))
        let a = AggregateActivity.make(from: [s], now: t0)
        XCTAssertEqual(a.mode, .working)
        XCTAssertEqual(a.iconStatus, .busy)
        XCTAssertNil(a.badge)
        XCTAssertEqual(a.text, "Bash · xcodebuild test")
        XCTAssertFalse(a.urgent)
    }

    func testWorkingElapsedMinutesSuffixAfterAMinute() {
        let s = busyWithTool(name: "Bash", preview: "build", startedAt: t0.addingTimeInterval(-135))
        let a = AggregateActivity.make(from: [s], now: t0)
        XCTAssertEqual(a.text, "Bash · build · 2m")
    }

    func testWorkingNoPreviewShowsToolNameOnly() {
        let s = busyWithTool(name: "Read", preview: "", startedAt: t0.addingTimeInterval(-5))
        let a = AggregateActivity.make(from: [s], now: t0)
        XCTAssertEqual(a.text, "Read")
    }

    func testWorkingMultiBadgesCountAndLeadsWithFreshest() {
        // pid 2 updated more recently → it's the lead.
        let older = busyWithTool(name: "Bash", preview: "old", startedAt: t0.addingTimeInterval(-30),
                                 pid: 1, updatedAt: t0.addingTimeInterval(-20))
        let fresher = busyWithTool(name: "Read", preview: "queue.ts", startedAt: t0.addingTimeInterval(-8),
                                   pid: 2, updatedAt: t0.addingTimeInterval(-2))
        let a = AggregateActivity.make(from: [older, fresher], now: t0)
        XCTAssertEqual(a.mode, .working)
        XCTAssertEqual(a.badge, "2")
        XCTAssertEqual(a.text, "Read · queue.ts")
    }

    func testBusyWithoutToolFallsBackToTitle() {
        var e = EnrichedSession.empty
        e.aiTitle = "Refactor retry queue"
        let s = snap(.busy, enriched: e)
        let a = AggregateActivity.make(from: [s], now: t0)
        XCTAssertEqual(a.mode, .working)
        XCTAssertEqual(a.text, "Refactor retry queue")
    }

    func testBusyWithoutToolOrTitleSaysWorking() {
        let a = AggregateActivity.make(from: [snap(.busy, enriched: EnrichedSession.empty)], now: t0)
        XCTAssertEqual(a.text, "working")
    }

    // MARK: - Needs you

    func testWaitingShowsApprovalTarget() {
        var e = EnrichedSession.empty
        e.activeTools = [ActiveTool(id: "q", name: "Bash", preview: "rm -rf build",
                                    startedAt: t0.addingTimeInterval(-5))]
        let a = AggregateActivity.make(from: [snap(.waiting, enriched: e)], now: t0)
        XCTAssertEqual(a.mode, .needsYou)
        XCTAssertEqual(a.iconStatus, .waiting)
        XCTAssertNil(a.badge)
        XCTAssertEqual(a.text, "approve Bash · rm -rf build")
        XCTAssertTrue(a.urgent)
    }

    func testWaitingWithoutPendingToolSaysNeedsInput() {
        let a = AggregateActivity.make(from: [snap(.waiting, enriched: EnrichedSession.empty)], now: t0)
        XCTAssertEqual(a.text, "needs input")
        XCTAssertTrue(a.urgent)
    }

    func testErrorShowsFailedTool() {
        var e = EnrichedSession.empty
        let failed = ActiveTool(id: "e", name: "Bash", preview: "python x.py",
                                startedAt: t0.addingTimeInterval(-40))
        e.recentTools = [CompletedTool(completing: failed, isError: true, at: t0.addingTimeInterval(-30))]
        let a = AggregateActivity.make(from: [snap(.error, enriched: e)], now: t0)
        XCTAssertEqual(a.mode, .needsYou)
        XCTAssertEqual(a.iconStatus, .error)
        XCTAssertEqual(a.text, "Bash failed")
        XCTAssertTrue(a.urgent)
    }

    func testErrorWithoutRecentToolSaysError() {
        let a = AggregateActivity.make(from: [snap(.error, enriched: EnrichedSession.empty)], now: t0)
        XCTAssertEqual(a.text, "error")
    }

    func testMultipleNeedsYouBadgesCountErrorIconWins() {
        var w = EnrichedSession.empty
        w.activeTools = [ActiveTool(id: "q", name: "Bash", preview: "x", startedAt: t0)]
        let a = AggregateActivity.make(from: [
            snap(.waiting, pid: 1, enriched: w),
            snap(.error, pid: 2, enriched: EnrichedSession.empty),
        ], now: t0)
        XCTAssertEqual(a.mode, .needsYou)
        XCTAssertEqual(a.badge, "2")
        XCTAssertEqual(a.text, "need you")
        XCTAssertEqual(a.iconStatus, .error)
    }

    // MARK: - Priority

    func testNeedsYouBeatsWorking() {
        let busy = busyWithTool(name: "Bash", preview: "build", startedAt: t0, pid: 1)
        var w = EnrichedSession.empty
        w.activeTools = [ActiveTool(id: "q", name: "Edit", preview: "file.swift", startedAt: t0)]
        let waiting = snap(.waiting, pid: 2, enriched: w)
        let a = AggregateActivity.make(from: [busy, waiting], now: t0)
        XCTAssertEqual(a.mode, .needsYou)
        XCTAssertEqual(a.text, "approve Edit · file.swift")
    }
}
