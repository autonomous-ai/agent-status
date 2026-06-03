import XCTest
@testable import AgentStatus

/// Tests for ClaudeCodeProvider.resolveStatus — the transcript-derived status
/// inference used when the pid.json `status` field is null/missing (some Claude
/// embeddings, e.g. the Agent SDK, write sessions without a status).
final class StatusResolutionTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 100_000)

    private func active(_ name: String) -> ActiveTool {
        ActiveTool(id: name, name: name, preview: "", startedAt: Date(timeIntervalSinceReferenceDate: 0), rawInputJSON: nil)
    }

    private func completed(_ name: String) -> CompletedTool {
        let a = active(name)
        return CompletedTool(completing: a, isError: false, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    // MARK: - Inference fills in a missing status

    func testActiveToolsInferBusy() {
        var e = EnrichedSession.empty
        e.activeTools = [active("Bash")]
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: e), .busy)
    }

    func testCurrentToolInfersBusy() {
        var e = EnrichedSession.empty
        e.currentTool = active("Edit")
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: e), .busy)
    }

    func testStopReasonToolUseInfersBusy() {
        var e = EnrichedSession.empty
        e.lastStopReason = "tool_use"
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: e), .busy)
    }

    func testAssistantTurnsInferIdle() {
        var e = EnrichedSession.empty
        e.assistantTurns = 3
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: e), .idle)
    }

    func testRecentToolsInferIdle() {
        var e = EnrichedSession.empty
        e.recentTools = [completed("Bash")]
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: e), .idle)
    }

    func testEmptyRawStatusIsAlsoTreatedAsMissing() {
        var e = EnrichedSession.empty
        e.activeTools = [active("Bash")]
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown(""), enriched: e), .busy)
    }

    // MARK: - Inference does NOT override or fabricate

    func testNoEnrichedLeavesUnknown() {
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: nil), .unknown("unknown"))
    }

    func testNoSignalLeavesUnknown() {
        // enriched exists but carries no activity signal yet → stay unknown.
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .unknown("unknown"), enriched: .empty), .unknown("unknown"))
    }

    func testRecognizedStatusIsNeverOverridden() {
        var e = EnrichedSession.empty
        e.activeTools = [active("Bash")]
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .idle, enriched: e), .idle)
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .busy, enriched: e), .busy)
        XCTAssertEqual(ClaudeCodeProvider.resolveStatus(coarse: .waiting, enriched: e), .waiting)
    }

    func testNamedFutureStatusIsPreserved() {
        // A genuinely new *named* status (forward-compat) must not be clobbered.
        var e = EnrichedSession.empty
        e.activeTools = [active("Bash")]
        XCTAssertEqual(
            ClaudeCodeProvider.resolveStatus(coarse: .unknown("compacting"), enriched: e),
            .unknown("compacting")
        )
    }
}
