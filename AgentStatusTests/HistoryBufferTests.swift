import XCTest
@testable import AgentStatus

@MainActor
final class HistoryBufferTests: XCTestCase {
    func testAppendDistinctStatusesAccumulate() {
        let buf = HistoryBuffer(cap: 10)
        let t0 = Date()
        buf.append(.init(timestamp: t0, status: .idle))
        buf.append(.init(timestamp: t0.addingTimeInterval(1), status: .busy))
        buf.append(.init(timestamp: t0.addingTimeInterval(2), status: .waiting))
        XCTAssertEqual(buf.samples.count, 3)
        XCTAssertEqual(buf.samples.map(\.status), [.idle, .busy, .waiting])
    }

    func testAppendCoalescesIdenticalTail() {
        let buf = HistoryBuffer(cap: 10)
        let t0 = Date()
        buf.append(.init(timestamp: t0, status: .busy))
        buf.append(.init(timestamp: t0.addingTimeInterval(1), status: .busy))
        buf.append(.init(timestamp: t0.addingTimeInterval(2), status: .busy))
        XCTAssertEqual(buf.samples.count, 1)
        XCTAssertEqual(buf.samples.last?.timestamp, t0.addingTimeInterval(2))
    }

    func testCapTrimsOldest() {
        let buf = HistoryBuffer(cap: 3)
        let t0 = Date()
        // 4 distinct statuses (none coalesced); cap=3 → expect only the last 3.
        buf.append(.init(timestamp: t0, status: .idle))
        buf.append(.init(timestamp: t0.addingTimeInterval(1), status: .busy))
        buf.append(.init(timestamp: t0.addingTimeInterval(2), status: .waiting))
        buf.append(.init(timestamp: t0.addingTimeInterval(3), status: .error))
        XCTAssertEqual(buf.samples.count, 3)
        XCTAssertEqual(buf.samples.map(\.status), [.busy, .waiting, .error])
    }

    func testBucketingForwardFills() {
        let buf = HistoryBuffer()
        let now = Date()
        buf.append(.init(timestamp: now.addingTimeInterval(-50), status: .idle))
        buf.append(.init(timestamp: now.addingTimeInterval(-20), status: .busy))
        let strip = buf.bucket(into: 6, span: 60, now: now)
        XCTAssertEqual(strip.count, 6)
        // After forward-fill, no nils once we've crossed the first sample.
        XCTAssertNotNil(strip.last as Any?)
        XCTAssertEqual(strip.last??.precedence, SessionStatus.busy.precedence)
    }

    // MARK: - Token series (Commander spend sparkline)

    func testTokenChangeIsNotCoalesced() {
        // Same status but growing tokens must each be retained, else the spend
        // curve would collapse to a single point.
        let buf = HistoryBuffer(cap: 10)
        let t0 = Date()
        buf.append(.init(timestamp: t0, status: .busy, tokens: 100))
        buf.append(.init(timestamp: t0.addingTimeInterval(1), status: .busy, tokens: 200))
        buf.append(.init(timestamp: t0.addingTimeInterval(2), status: .busy, tokens: 200))  // unchanged → coalesced
        XCTAssertEqual(buf.samples.count, 2)
        XCTAssertEqual(buf.samples.map(\.tokens), [100, 200])
    }

    func testTokenSeriesIsCumulativeAndForwardFills() {
        let buf = HistoryBuffer()
        let now = Date()
        buf.append(.init(timestamp: now.addingTimeInterval(-50), status: .busy, tokens: 1_000))
        buf.append(.init(timestamp: now.addingTimeInterval(-20), status: .busy, tokens: 4_000))
        let series = buf.tokenSeries(into: 6, span: 60, now: now)
        XCTAssertEqual(series.count, 6)
        // Forward-filled to the latest known total at the right edge.
        XCTAssertEqual(series.last ?? nil, 4_000)
        // Non-decreasing across the filled portion (cumulative).
        let filled = series.compactMap { $0 }
        XCTAssertEqual(filled, filled.sorted())
    }
}
