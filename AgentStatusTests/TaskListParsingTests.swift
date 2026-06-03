import XCTest
@testable import AgentStatus

/// Drives TranscriptTailer with TaskCreate/TaskUpdate/TodoWrite tool_use lines
/// and asserts the accumulated `EnrichedSession.todos`. Also covers the pure
/// `apply*` helpers directly.
final class TaskListParsingTests: XCTestCase {

    private func jsonString(_ obj: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
    }

    /// One assistant message carrying a single tool_use with the given input.
    private func toolUse(_ name: String, _ input: [String: Any], id: String = "t") -> String {
        jsonString([
            "type": "assistant",
            "message": ["content": [
                ["type": "tool_use", "id": id, "name": name, "input": input],
            ]],
        ])
    }

    // MARK: - Task tools (TaskCreate / TaskUpdate)

    func testTaskCreateThenUpdatesTrackStatus() async {
        let t = TranscriptTailer(sessionId: "tasks", cwd: URL(fileURLWithPath: "/tmp"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "A1: rewrite", "activeForm": "Rewriting"], id: "a"))

        var s = await t._test_state
        XCTAssertEqual(s.todos.count, 1)
        XCTAssertEqual(s.todos.first?.id, "1")
        XCTAssertEqual(s.todos.first?.title, "A1: rewrite")
        XCTAssertEqual(s.todos.first?.activeForm, "Rewriting")
        XCTAssertEqual(s.todos.first?.status, .pending)

        await t._test_processLine(toolUse("TaskUpdate", ["taskId": "1", "status": "in_progress"], id: "b"))
        s = await t._test_state
        XCTAssertEqual(s.todos.first?.status, .inProgress)

        await t._test_processLine(toolUse("TaskUpdate", ["taskId": "1", "status": "completed"], id: "c"))
        s = await t._test_state
        XCTAssertEqual(s.todos.first?.status, .completed)
    }

    func testMultipleTaskCreatesGetSequentialIds() async {
        let t = TranscriptTailer(sessionId: "seq", cwd: URL(fileURLWithPath: "/tmp"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "first"], id: "a"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "second"], id: "b"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "third"], id: "c"))
        let s = await t._test_state
        XCTAssertEqual(s.todos.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(s.todos.map(\.title), ["first", "second", "third"])
    }

    func testDeletedTaskIsFilteredOut() async {
        let t = TranscriptTailer(sessionId: "del", cwd: URL(fileURLWithPath: "/tmp"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "keep"], id: "a"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "drop"], id: "b"))
        await t._test_processLine(toolUse("TaskUpdate", ["taskId": "2", "status": "deleted"], id: "c"))
        let s = await t._test_state
        XCTAssertEqual(s.todos.map(\.title), ["keep"])
    }

    func testUpdateUnknownTaskIdIsIgnored() async {
        let t = TranscriptTailer(sessionId: "unk", cwd: URL(fileURLWithPath: "/tmp"))
        await t._test_processLine(toolUse("TaskCreate", ["subject": "only"], id: "a"))
        await t._test_processLine(toolUse("TaskUpdate", ["taskId": "99", "status": "completed"], id: "b"))
        let s = await t._test_state
        XCTAssertEqual(s.todos.count, 1)
        XCTAssertEqual(s.todos.first?.status, .pending)
    }

    func testLegacyBatchTaskCreate() async {
        let t = TranscriptTailer(sessionId: "legacy", cwd: URL(fileURLWithPath: "/tmp"))
        let tasksJSON = "[{\"name\":\"Set up env\",\"status\":\"in_progress\"},{\"name\":\"Build\",\"status\":\"pending\"}]"
        await t._test_processLine(toolUse("TaskCreate", ["taskListName": "candy", "tasks": tasksJSON], id: "a"))
        let s = await t._test_state
        XCTAssertEqual(s.todos.map(\.title), ["Set up env", "Build"])
        XCTAssertEqual(s.todos.map(\.id), ["1", "2"])
        XCTAssertEqual(s.todos.first?.status, .inProgress)
    }

    // MARK: - TodoWrite (wholesale replace)

    func testTodoWriteReplacesEntireList() async {
        let t = TranscriptTailer(sessionId: "todo", cwd: URL(fileURLWithPath: "/tmp"))
        await t._test_processLine(toolUse("TodoWrite", ["todos": [
            ["content": "alpha", "status": "completed", "activeForm": "Alphaing"],
            ["content": "beta", "status": "in_progress", "activeForm": "Betaing"],
            ["content": "gamma", "status": "pending"],
        ]], id: "a"))
        var s = await t._test_state
        XCTAssertEqual(s.todos.map(\.title), ["alpha", "beta", "gamma"])
        XCTAssertEqual(s.todos[1].status, .inProgress)
        XCTAssertEqual(s.todos[1].activeForm, "Betaing")

        // A second TodoWrite replaces, not appends.
        await t._test_processLine(toolUse("TodoWrite", ["todos": [
            ["content": "only one now", "status": "pending"],
        ]], id: "b"))
        s = await t._test_state
        XCTAssertEqual(s.todos.map(\.title), ["only one now"])
    }

    // MARK: - Pure helpers

    func testApplyTaskUpdateAcceptsIntTaskId() {
        var list = [TodoItem(id: "1", title: "x", activeForm: nil, status: .pending)]
        TranscriptTailer.applyTaskUpdate(["taskId": 1, "status": "completed"], into: &list)
        XCTAssertEqual(list.first?.status, .completed)
    }

    func testApplyTodoWriteSkipsEmptyTitles() {
        let items = TranscriptTailer.applyTodoWrite(["todos": [
            ["content": "", "status": "pending"],
            ["content": "real", "status": "pending"],
        ]])
        XCTAssertEqual(items.map(\.title), ["real"])
    }

    // MARK: - coreEqual republish gate

    func testTodosChangeBreaksCoreEqual() {
        var a = EnrichedSession.empty
        var b = EnrichedSession.empty
        XCTAssertTrue(a.coreEqual(b))
        a.todos = [TodoItem(id: "1", title: "x", activeForm: nil, status: .pending)]
        XCTAssertFalse(a.coreEqual(b), "a todos change must break coreEqual so the UI republishes")
        b.todos = [TodoItem(id: "1", title: "x", activeForm: nil, status: .pending)]
        XCTAssertTrue(a.coreEqual(b))
    }
}
