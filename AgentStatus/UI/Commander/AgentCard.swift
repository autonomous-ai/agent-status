import SwiftUI

/// A bold, status-colored agent tile on the Commander board. Communicates through
/// color, size, and visual gauges (status ring, task ring, area chart, big
/// numbers) rather than small text. A thin renderer over `AgentCardModel`; the
/// parent supplies a shared 1 Hz `now`.
struct AgentCard: View {
    let model: AgentCardModel
    let buckets: [SessionStatus?]
    let isSelected: Bool
    var onTap: () -> Void

    @EnvironmentObject var settings: Settings
    @State private var hovering = false

    private var accent: Color { model.status.color }

    /// How loud the card is — urgent states glow hard, idle recedes.
    private var glowStrength: Double {
        if model.dim { return 0 }
        switch model.status {
        case .error:            return 0.55
        case .waiting:          return 0.5
        case .busy, .running:   return 0.3
        default:                return 0.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroAction
            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(surface)
        .overlay(border)
        .shadow(color: accent.opacity(glowStrength), radius: hovering ? 26 : 20, y: 6)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .scaleEffect(hovering ? 1.012 : 1)
        .opacity(model.dim ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: - Surface & border

    private var surface: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(model.dim ? 0.04 : 0.18),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }

    @ViewBuilder
    private var border: some View {
        if model.status == .error && !model.dim {
            // Pulsing red edge for errors.
            TimelineView(.periodic(from: .now, by: 0.9)) { ctx in
                let phase = Int(ctx.date.timeIntervalSinceReferenceDate / 0.9) % 2
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(phase == 0 ? 0.9 : 0.4), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.9), value: phase)
            }
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isSelected ? accent.opacity(0.9) : accent.opacity(model.dim ? 0.15 : 0.4),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusRingIcon(status: model.status, size: 30, dim: model.dim)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.uptime)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if model.hasRecentError {
                    Label("error", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    // MARK: - Hero action

    @ViewBuilder
    private var heroAction: some View {
        if model.activity.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                Text(model.status == .idle ? "Resting" : model.statusLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 9) {
                Image(systemName: model.isWaiting ? "bell.badge.fill" : "bolt.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(model.isWaiting ? .orange : accent)
                    .symbolRenderingMode(.hierarchical)
                Text(model.activity)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.isWaiting ? Color.orange : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !model.activityElapsed.isEmpty {
                    Spacer(minLength: 4)
                    Text(model.activityElapsed)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((model.isWaiting ? Color.orange : accent).opacity(0.12))
            )
        }
    }

    // MARK: - Footer (gauges)

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            if settings.showTaskList && model.hasTasks {
                TaskRing(completed: model.tasksCompleted, total: model.tasksTotal, size: 46)
            }
            if settings.showTokensAndCost && !model.tokens.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.tokens)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if !model.cost.isEmpty {
                        Text(model.cost)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 8)
            BoldSparkline(buckets: buckets, tint: accent, height: 40)
                .frame(maxWidth: 150)
        }
    }
}
