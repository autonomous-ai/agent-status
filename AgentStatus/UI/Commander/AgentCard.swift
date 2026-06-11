import SwiftUI

/// A bold, status-colored agent tile on the Commander board. Communicates through
/// color, size, and visual gauges (status ring, task ring, area chart, big
/// numbers) rather than small text. A thin renderer over `AgentCardModel`; the
/// parent supplies a shared 1 Hz `now`.
struct AgentCard: View {
    let model: AgentCardModel
    let spend: [Double?]          // cumulative token totals over the last window
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
        VStack(alignment: .leading, spacing: 12) {
            header
            autonomyRow
            heroAction
            infoRow
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
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(model.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let branch = model.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .semibold))
                            Text(branch)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }
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

    /// Busy/running with no tool in flight — the model is generating, not resting.
    private var isThinking: Bool {
        model.activity.isEmpty && !model.dim
            && (model.status == .busy || model.status == .running)
    }

    @ViewBuilder
    private var heroAction: some View {
        if isThinking {
            HStack(spacing: 9) {
                Image(systemName: "ellipsis.bubble.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
                // Surface what it just did rather than a bare "Thinking…"; the
                // elapsed timer then reads as "how long it's been generating since".
                if let last = model.lastAction {
                    Text("just ")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    + Text(last)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("Thinking…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                }
                if !model.thinkingElapsed.isEmpty {
                    Spacer(minLength: 4)
                    Text(model.thinkingElapsed)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.12))
            )
        } else if model.activity.isEmpty {
            // Quiet hero — nothing in flight. Status drives the glyph: an
            // errored or blocked session must not wear the "resting" moon.
            let (icon, tint): (String, Color) = switch model.status {
            case .error:   ("exclamationmark.triangle.fill", .red)
            case .waiting: ("bell.badge.fill", .orange)
            default:       ("moon.zzz.fill", .secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint)
                Text(model.status == .idle ? "Resting" : model.statusLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                if !model.idleFor.isEmpty {
                    Text("· \(model.idleFor)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        } else {
            HStack(spacing: 9) {
                Image(systemName: model.isWaiting ? "bell.badge.fill" : "bolt.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(model.isWaiting ? .orange : accent)
                    .symbolRenderingMode(.hierarchical)
                if model.activeToolCount > 1 {
                    Text("×\(model.activeToolCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(model.isWaiting ? Color.orange : accent)
                        .monospacedDigit()
                }
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

    // MARK: - Info row (current task + model/mode chips)

    /// Chip-worthy permission modes: anything but the default. `bypass` is a
    /// safety signal and reads red; `plan` is a "won't write" signal.
    private var visibleMode: String? {
        guard let m = model.permissionMode, m != "default" else { return nil }
        return m
    }

    /// Autonomy banner: surfaces an active `/goal` and/or `/loop`. These read as
    /// "this session is running itself" — an idle-looking goal/loop session is
    /// NOT done, so this sits high on the card where it can't be missed.
    @ViewBuilder
    private var autonomyRow: some View {
        if model.goalAchieved || model.goal != nil || model.loop != nil {
            HStack(spacing: 8) {
                // An achieved goal flips the banner from pink "pursuing" to green
                // "done" — so a resting goal session no longer reads as "stalled".
                if model.goalAchieved {
                    goalAchievedChip(summary: model.goalSummary)
                } else if let goal = model.goal {
                    autonomyChip(icon: "target", label: goal, tint: .pink)
                }
                if let loop = model.loop {
                    autonomyChip(icon: "repeat", label: loop, tint: .teal)
                        .layoutPriority(model.goal == nil ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Green "✓ Goal achieved · 12m · 1 turn · 53.2k" banner — the met-condition
    /// counterpart to the pink active-goal chip.
    private func goalAchievedChip(summary: String?) -> some View {
        let tint = Color.green
        return HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
            Text("Goal achieved")
                .font(.system(size: 11, weight: .semibold))
            if let summary {
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(model.dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(model.dim ? 0.06 : 0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(model.dim ? 0.15 : 0.4), lineWidth: 1))
    }

    private func autonomyChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(model.dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(model.dim ? 0.06 : 0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(model.dim ? 0.15 : 0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var infoRow: some View {
        if model.taskHeadline != nil || model.model != nil || visibleMode != nil {
            HStack(alignment: .center, spacing: 8) {
                if let headline = model.taskHeadline {
                    Text(headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if let mode = visibleMode {
                    chip(mode, tint: modeTint(mode))
                }
                if let mdl = model.model {
                    chip(mdl, tint: .gray)
                }
            }
        }
    }

    private func modeTint(_ mode: String) -> Color {
        switch mode {
        case "bypass": .red
        case "plan":   .purple
        default:       .gray
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .gray ? Color.secondary : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: - Footer (gauges)

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            if settings.showTaskList && model.hasTasks {
                TaskRing(completed: model.tasksCompleted, total: model.tasksTotal, size: 46)
            }
            if settings.showTokensAndCost && !model.tokens.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.tokens)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    if !model.cost.isEmpty {
                        Text(model.cost)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            if model.contextTokens > 0 {
                contextGauge
                    .fixedSize()
            }
            Spacer(minLength: 8)
            // The flexible element: the chart absorbs whatever width the fixed
            // stats leave over, down to nothing on the narrowest cards.
            BoldSparkline(values: spend, tint: accent, height: 40)
                .frame(maxWidth: 150)
        }
    }

    // MARK: - Context-window gauge

    /// How full the model's context window is right now — the "how close to
    /// auto-compaction" gauge. Cool below 60 %, orange to 85 %, red above.
    private var contextGauge: some View {
        let frac = model.contextFraction
        let tint: Color = frac > 0.85 ? .red : (frac > 0.6 ? .orange : .cyan)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text("ctx")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(2, 64 * frac))
            }
            .frame(width: 64, height: 4)
        }
        .help("\(TokenUsage.compact(model.contextTokens)) of \(TokenUsage.compact(model.contextLimit)) context window used")
        .accessibilityLabel("Context window \(Int((frac * 100).rounded())) percent full")
    }
}
