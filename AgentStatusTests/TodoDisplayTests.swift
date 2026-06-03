import XCTest
@testable import AgentStatus

/// Pure tests for TodoDisplay.rows — ordering (in_progress, pending, completed),
/// completed-overflow collapse, and the k/n counts.
final class TodoDisplayTests: XCTestCase {

    private func item(_ id: String, _ status: TodoStatus) -> TodoItem {
        TodoItem(id: id, title: "t\(id)", activeForm: nil, status: status)
    }

    func testOrderingInProgressThenPendingThenCompleted() {
        let todos = [
            item("1", .completed),
            item("2", .pending),
            item("3", .inProgress),
        ]
        let rows = TodoDisplay.rows(from: todos)
        XCTAssertEqual(rows.visible.map(\.id), ["3", "2", "1"])
        XCTAssertEqual(rows.completedCount, 1)
        XCTAssertEqual(rows.totalCount, 3)
        XCTAssertEqual(rows.hiddenCompletedCount, 0)
    }

    func testDeletedExcludedFromCountsAndRows() {
        let todos = [
            item("1", .pending),
            item("2", .deleted),
            item("3", .completed),
        ]
        let rows = TodoDisplay.rows(from: todos)
        XCTAssertEqual(rows.totalCount, 2)
        XCTAssertFalse(rows.visible.contains { $0.id == "2" })
    }

    func testCompletedOverflowCollapses() {
        // 2 actionable + 10 completed, maxVisible 8 → show 2 actionable + 6
        // completed, collapse the remaining 4.
        var todos = [item("a", .inProgress), item("b", .pending)]
        for i in 0..<10 { todos.append(item("c\(i)", .completed)) }
        let rows = TodoDisplay.rows(from: todos, maxVisible: 8)
        XCTAssertEqual(rows.visible.count, 8)
        XCTAssertEqual(rows.visible.prefix(2).map(\.id), ["a", "b"])
        XCTAssertEqual(rows.hiddenCompletedCount, 4)
        XCTAssertEqual(rows.completedCount, 10)
    }

    func testActionableNeverHidden() {
        // Many pending, no slots for completed → all actionable still shown,
        // all completed collapsed.
        var todos = (0..<10).map { item("p\($0)", .pending) }
        todos.append(item("done", .completed))
        let rows = TodoDisplay.rows(from: todos, maxVisible: 8)
        XCTAssertEqual(rows.visible.count, 10, "actionable items are never dropped")
        XCTAssertEqual(rows.hiddenCompletedCount, 1)
    }
}
