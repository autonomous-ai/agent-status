import Foundation

/// Pure selection logic for rendering a task/todo checklist in a bounded space:
/// in-progress items first, then pending, then as many completed as fit, with
/// the remaining completed collapsed into a "+N completed" count. Kept separate
/// from the SwiftUI view so the collapse behavior is unit-testable.
enum TodoDisplay {
    struct Rows: Equatable {
        let visible: [TodoItem]         // ordered: in_progress, pending, then shown completed
        let hiddenCompletedCount: Int   // completed not shown (collapsed)
        let completedCount: Int         // all completed (k in "k/n")
        let totalCount: Int             // all non-deleted (n in "k/n")
    }

    static func rows(from todos: [TodoItem], maxVisible: Int = 8) -> Rows {
        let live = todos.filter { $0.status != .deleted }
        let inProgress = live.filter { $0.status == .inProgress }
        let pending = live.filter { $0.status == .pending }
        let completed = live.filter { $0.status == .completed }

        // Actionable items (in-progress, then pending) always shown; completed
        // fills whatever slots remain, oldest-first, rest collapsed.
        let actionable = inProgress + pending
        let slotsForCompleted = max(0, maxVisible - actionable.count)
        let shownCompleted = Array(completed.prefix(slotsForCompleted))

        return Rows(
            visible: actionable + shownCompleted,
            hiddenCompletedCount: completed.count - shownCompleted.count,
            completedCount: completed.count,
            totalCount: live.count
        )
    }
}
