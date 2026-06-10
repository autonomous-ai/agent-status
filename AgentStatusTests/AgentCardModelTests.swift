import XCTest
@testable import AgentStatus

/// Pure-builder tests for `AgentCardModel.make(from:now:)`.
/// All cases use a pinned `now` so elapsed math is deterministic.
@MainActor
final class AgentCardModelTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 100_000)

    // MARK: - Title

    func testTitleUsesAITitleWhenPresent() {
        var e = EnrichedSession.empty
        e.aiTitle = "Investigate flake"
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertEqual(m.title, "Investigate flake")
    }

    func testTitleFallsBackToCwdBasename() {
        let snap = makeSnap(cwd: URL(fileURLWithPath: "/Users/dee/repos/agent-status"))
        let m = AgentCardModel.make(from: snap, now: t0)
        XCTAssertEqual(m.title, "agent-status")
        XCTAssertEqual(m.subtitle, "agent-status")
    }

    func testTitleForUUIDFolderUsesLastUserPrompt() {
        var e = EnrichedSession.empty
        e.lastUserPrompt = "  Build a phone stand  "
        let cwd = URL(fileURLWithPath: "/x/projects/625f5183-45e0-4c25-8761-dffc40ae9978")
        let m = AgentCardModel.make(from: makeSnap(cwd: cwd, enriched: e), now: t0)
        XCTAssertEqual(m.title, "Build a phone stand")
    }

    // MARK: - Grouping (attention bands)

    func testGroupNeedsYouForWaiting() {
        let m = AgentCardModel.make(from: makeSnap(status: .waiting), now: t0)
        XCTAssertEqual(m.group, .needsYou)
    }

    func testGroupNeedsYouForError() {
        let m = AgentCardModel.make(from: makeSnap(status: .error), now: t0)
        XCTAssertEqual(m.group, .needsYou)
    }

    func testGroupWorkingForBusyAndRunning() {
        XCTAssertEqual(AgentCardModel.make(from: makeSnap(status: .busy), now: t0).group, .working)
        XCTAssertEqual(AgentCardModel.make(from: makeSnap(status: .running), now: t0).group, .working)
    }

    func testGroupIdleForIdle() {
        XCTAssertEqual(AgentCardModel.make(from: makeSnap(status: .idle), now: t0).group, .idle)
    }

    func testGroupEndedWhenNotAlive() {
        // Dead trumps status — a dead "busy" session is Ended, not Working.
        let m = AgentCardModel.make(from: makeSnap(status: .busy, isAlive: false), now: t0)
        XCTAssertEqual(m.group, .ended)
        XCTAssertTrue(m.dim)
    }

    func testGroupOrderIsUrgencyDescending() {
        XCTAssertLessThan(CommanderGroup.needsYou.rawValue, CommanderGroup.working.rawValue)
        XCTAssertLessThan(CommanderGroup.working.rawValue, CommanderGroup.idle.rawValue)
        XCTAssertLessThan(CommanderGroup.idle.rawValue, CommanderGroup.ended.rawValue)
    }

    // MARK: - Activity line

    func testIdleHasNoActivity() {
        let m = AgentCardModel.make(from: makeSnap(status: .idle), now: t0)
        XCTAssertEqual(m.activity, "")
        XCTAssertEqual(m.activityElapsed, "")
        XCTAssertFalse(m.isWaiting)
        XCTAssertEqual(m.statusLabel, "Idle")
    }

    func testBusySingleToolShowsToolAndElapsed() {
        var e = EnrichedSession.empty
        e.activeTools = [tool(name: "Bash", preview: "xcodebuild test", startedAt: t0.addingTimeInterval(-90))]
        let m = AgentCardModel.make(from: makeSnap(status: .busy, enriched: e), now: t0)
        XCTAssertEqual(m.activity, "Bash · xcodebuild test")
        XCTAssertEqual(m.activityElapsed, "1m 30s")
        XCTAssertFalse(m.isWaiting)
        XCTAssertEqual(m.activeToolCount, 1)
    }

    func testBusyMultiToolNamesFirstTwoPlusOverflow() {
        var e = EnrichedSession.empty
        e.activeTools = [
            tool(name: "Bash", preview: "make", startedAt: t0.addingTimeInterval(-10)),
            tool(name: "Read", preview: "a.swift", startedAt: t0.addingTimeInterval(-8)),
            tool(name: "Grep", preview: "foo", startedAt: t0.addingTimeInterval(-6)),
        ]
        let m = AgentCardModel.make(from: makeSnap(status: .busy, enriched: e), now: t0)
        XCTAssertEqual(m.activity, "Bash, Read +1")
        XCTAssertEqual(m.activeToolCount, 3)
        // Elapsed anchors to the earliest active tool.
        XCTAssertEqual(m.activityElapsed, "10s")
    }

    func testBusyEmptyPreviewShowsToolNameOnly() {
        var e = EnrichedSession.empty
        e.activeTools = [tool(name: "Read", preview: "   ", startedAt: t0)]
        let m = AgentCardModel.make(from: makeSnap(status: .busy, enriched: e), now: t0)
        XCTAssertEqual(m.activity, "Read")
    }

    func testWaitingShowsApprovalTargetAndIsWaiting() {
        var e = EnrichedSession.empty
        e.activeTools = [
            tool(name: "Read", preview: "a.swift", startedAt: t0.addingTimeInterval(-30)),
            tool(name: "Bash", preview: "rm -rf build", startedAt: t0.addingTimeInterval(-5)),
        ]
        let m = AgentCardModel.make(from: makeSnap(status: .waiting, enriched: e), now: t0)
        XCTAssertEqual(m.activity, "approve Bash · rm -rf build")
        XCTAssertEqual(m.activityElapsed, "5s")
        XCTAssertTrue(m.isWaiting)
    }

    // MARK: - Tasks

    func testTasksCountAndInProgressHeadline() {
        var e = EnrichedSession.empty
        e.todos = [
            TodoItem(id: "0", title: "Write parser", activeForm: "Writing parser", status: .completed),
            TodoItem(id: "1", title: "Rewrite tokenizer", activeForm: "Rewriting tokenizer", status: .inProgress),
            TodoItem(id: "2", title: "Add tests", activeForm: nil, status: .pending),
            TodoItem(id: "3", title: "Dropped", activeForm: nil, status: .deleted),
        ]
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertTrue(m.hasTasks)
        XCTAssertEqual(m.tasksTotal, 3)            // deleted excluded
        XCTAssertEqual(m.tasksCompleted, 1)
        XCTAssertEqual(m.taskHeadline, "▸ Rewriting tokenizer")  // activeForm preferred
        XCTAssertEqual(m.taskFraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testTaskHeadlineFallsBackToNextPending() {
        var e = EnrichedSession.empty
        e.todos = [
            TodoItem(id: "0", title: "Done thing", activeForm: nil, status: .completed),
            TodoItem(id: "1", title: "Next thing", activeForm: nil, status: .pending),
        ]
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertEqual(m.taskHeadline, "▸ Next thing")
    }

    func testNoTasksWhenEmpty() {
        let m = AgentCardModel.make(from: makeSnap(enriched: .empty), now: t0)
        XCTAssertFalse(m.hasTasks)
        XCTAssertNil(m.taskHeadline)
        XCTAssertEqual(m.tasksTotal, 0)
    }

    // MARK: - Spend / context

    func testTokensCostModelAndModeFormatted() {
        var e = EnrichedSession.empty
        e.tokens = TokenUsage(input: 200_000, output: 48_000, cacheRead: 0, cacheCreation: 0)
        e.estimatedCost = 1.234
        e.currentModel = "claude-opus-4-8"
        e.permissionMode = "bypassPermissions"
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertEqual(m.tokens, "248k")
        XCTAssertEqual(m.cost, "$1.23")
        XCTAssertEqual(m.model, "opus-4-8")        // "claude-" stripped
        XCTAssertEqual(m.permissionMode, "bypass") // shortened
    }

    func testPlanModePassesThrough() {
        var e = EnrichedSession.empty
        e.permissionMode = "plan"
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertEqual(m.permissionMode, "plan")
    }

    func testZeroTokensProduceEmptyStrings() {
        let m = AgentCardModel.make(from: makeSnap(enriched: .empty), now: t0)
        XCTAssertEqual(m.tokens, "")
        XCTAssertEqual(m.cost, "")
        XCTAssertNil(m.model)
    }

    // MARK: - Errors

    func testRecentErrorFlag() {
        var e = EnrichedSession.empty
        e.recentTools = [completion(isError: true)]
        let m = AgentCardModel.make(from: makeSnap(enriched: e), now: t0)
        XCTAssertTrue(m.hasRecentError)
    }

    func testRecentErrorDoesNotRebucketBusySession() {
        // A busy session with a past error stays in Working; the pip carries the
        // error, not the grouping.
        var e = EnrichedSession.empty
        e.recentTools = [completion(isError: true)]
        let m = AgentCardModel.make(from: makeSnap(status: .busy, enriched: e), now: t0)
        XCTAssertEqual(m.group, .working)
        XCTAssertTrue(m.hasRecentError)
    }

    // MARK: - Helpers

    private func tool(name: String, preview: String, startedAt: Date) -> ActiveTool {
        ActiveTool(id: UUID().uuidString, name: name, preview: preview, startedAt: startedAt, rawInputJSON: nil)
    }

    private func completion(isError: Bool) -> CompletedTool {
        let a = ActiveTool(id: UUID().uuidString, name: "Bash", preview: "x",
                           startedAt: t0.addingTimeInterval(-1), rawInputJSON: nil)
        return CompletedTool(completing: a, isError: isError, at: t0)
    }

    private func makeSnap(
        status: SessionStatus = .idle,
        cwd: URL = URL(fileURLWithPath: "/tmp/sample"),
        isAlive: Bool = true,
        enriched: EnrichedSession? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: "p:s",
            providerId: "p",
            pid: 1,
            sessionId: "s",
            cwd: cwd,
            startedAt: t0.addingTimeInterval(-200),
            updatedAt: t0,
            status: status,
            waitingFor: status == .waiting ? "tool:Bash" : nil,
            version: nil,
            kind: nil,
            entrypoint: nil,
            isAlive: isAlive,
            enriched: enriched ?? EnrichedSession.empty
        )
    }
}
