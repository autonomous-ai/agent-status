import SwiftUI

/// Bold, filled gradient area chart of the last `span` seconds of session
/// activity — a vivid sibling of the menu bar's thin `SparklineView`. Same
/// bucket data (`HistoryBuffer.bucket(into:span:)`), but rendered as a smooth
/// filled area with a bright top line so it reads as a chart on the board.
struct BoldSparkline: View {
    let buckets: [SessionStatus?]
    var tint: Color = .blue
    var height: CGFloat = 40

    var body: some View {
        Canvas { ctx, size in
            guard buckets.count > 1 else { return }
            let n = CGFloat(buckets.count - 1)
            let stepX = size.width / n
            // Map each bucket to a normalized height; nil → baseline.
            let pts: [CGPoint] = buckets.enumerated().map { i, b in
                let weight = b.map(Self.activityWeight) ?? 0.05
                let y = size.height - max(2, size.height * weight)
                return CGPoint(x: CGFloat(i) * stepX, y: y)
            }

            // Filled area (line → down to baseline → back).
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            area.addLine(to: pts[0])
            for p in pts.dropFirst() { area.addLine(to: p) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.45), tint.opacity(0.04)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            // Bright top line.
            var line = Path()
            line.move(to: pts[0])
            for p in pts.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Visual weight per status — mirrors `SparklineView.activityHeight` so the
    /// two charts agree on what "tall" means.
    static func activityWeight(_ status: SessionStatus) -> CGFloat {
        switch status {
        case .error:   1.0
        case .waiting: 0.85
        case .busy:    0.85
        case .running: 0.7
        case .idle:    0.25
        case .paused:  0.15
        case .stopped: 0.1
        case .unknown: 0.15
        }
    }
}
