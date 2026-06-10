import SwiftUI

/// Circular task-progress gauge: a status-colored arc over a faint track, with
/// the `completed/total` count centered. A visual stand-in for the old thin bar
/// + "3/8" label — reads at a glance on the Commander board.
struct TaskRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 46

    private var fraction: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }
    private var done: Bool { total > 0 && completed == total }
    private var tint: Color { done ? .green : .blue }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.75), tint]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: 4)
            VStack(spacing: 0) {
                Text("\(completed)")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Rectangle().fill(.secondary.opacity(0.5)).frame(width: size * 0.34, height: 1)
                Text("\(total)")
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: fraction)
        .accessibilityLabel("\(completed) of \(total) tasks done")
    }
}
