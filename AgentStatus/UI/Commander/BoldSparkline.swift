import SwiftUI

/// Bold, filled gradient area chart of a session's recent token-spend curve —
/// the cumulative grand-total over the last span, normalized to its own min/max.
/// A climbing line means the agent is actively burning tokens; a flat one means
/// it's stalled. Sits beside the big token/cost number so the two read together.
struct BoldSparkline: View {
    /// Cumulative token totals, one per time bucket (oldest → newest). `nil`
    /// entries are leading gaps before the session's first sample.
    let values: [Double?]
    var tint: Color = .blue
    var height: CGFloat = 40

    var body: some View {
        Canvas { ctx, size in
            let known = values.compactMap { $0 }
            guard known.count > 1 else { return }
            let lo = known.min() ?? 0
            let hi = known.max() ?? 0
            let range = hi - lo

            let n = CGFloat(values.count - 1)
            let stepX = size.width / n
            // Normalize each value into the card window's own range; a flat
            // (no-spend) window collapses to a thin line along the baseline.
            let pts: [CGPoint] = values.enumerated().map { i, v in
                let weight: CGFloat = (range > 0) ? CGFloat(((v ?? lo) - lo) / range) : 0
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
}
