import Foundation

/// One point in a session's status timeline. The sparkline views draw these.
/// `tokens` is the cumulative grand-total at sample time — it's what the
/// Commander token-velocity sparkline plots; the menu-bar status strip ignores it.
struct SessionHistorySample: Hashable, Sendable {
    let timestamp: Date
    let status: SessionStatus
    let tokens: Int

    init(timestamp: Date, status: SessionStatus, tokens: Int = 0) {
        self.timestamp = timestamp
        self.status = status
        self.tokens = tokens
    }
}
