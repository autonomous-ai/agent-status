import Foundation

/// Per-session ring buffer of status samples for the sparkline view.
/// Capped to `cap` (default 120 ≈ 2 minutes at 1 sample/sec).
@MainActor
final class HistoryBuffer {
    let cap: Int
    private(set) var samples: [SessionHistorySample] = []

    init(cap: Int = 120) { self.cap = cap }

    /// Append a sample; coalesces a truly-unchanged tail (same status AND same
    /// token total) by updating its timestamp, so the status strip shows
    /// transitions not duplicate plateaus. A token change is NOT coalesced — the
    /// token-velocity sparkline needs the intermediate points to draw a curve.
    func append(_ sample: SessionHistorySample) {
        if let last = samples.last, last.status == sample.status, last.tokens == sample.tokens {
            samples[samples.count - 1] = sample
            return
        }
        samples.append(sample)
        if samples.count > cap {
            samples.removeFirst(samples.count - cap)
        }
    }

    /// Down-sample to `bucketCount` columns by taking the most-recent status in each time slice.
    /// Used by SparklineView to render a fixed-width strip.
    func bucket(into bucketCount: Int, span: TimeInterval, now: Date = Date()) -> [SessionStatus?] {
        guard bucketCount > 0 else { return [] }
        let start = now.addingTimeInterval(-span)
        let slice = span / Double(bucketCount)
        var out = [SessionStatus?](repeating: nil, count: bucketCount)
        for s in samples where s.timestamp >= start {
            let i = min(bucketCount - 1, Int(s.timestamp.timeIntervalSince(start) / slice))
            out[i] = s.status
        }
        // Forward-fill so a long-held status fills the bucket strip rather than blinking.
        var carry: SessionStatus? = nil
        for i in 0..<bucketCount {
            if let s = out[i] { carry = s } else { out[i] = carry }
        }
        return out
    }

    /// Down-sample the cumulative token total into `bucketCount` columns over the
    /// last `span` seconds — the most-recent (highest) total per slice, forward-
    /// filled. Feeds the Commander token-velocity sparkline: a rising curve means
    /// the agent is actively spending, a flat one means it's stalled. `nil`
    /// columns are leading gaps before the first sample (a young session).
    func tokenSeries(into bucketCount: Int, span: TimeInterval, now: Date = Date()) -> [Double?] {
        guard bucketCount > 0 else { return [] }
        let start = now.addingTimeInterval(-span)
        let slice = span / Double(bucketCount)
        var out = [Double?](repeating: nil, count: bucketCount)
        for s in samples where s.timestamp >= start {
            let i = min(bucketCount - 1, Int(s.timestamp.timeIntervalSince(start) / slice))
            // Cumulative total → the latest (largest) value in a slice wins.
            out[i] = max(out[i] ?? 0, Double(s.tokens))
        }
        var carry: Double? = nil
        for i in 0..<bucketCount {
            if let v = out[i] { carry = v } else { out[i] = carry }
        }
        return out
    }
}
