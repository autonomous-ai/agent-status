import SwiftUI

/// One row in the dashboard popover list. A thin renderer over `AgentCardModel`
/// — the same tested view-model the Commander board cards use — so all three
/// surfaces (menu-bar items, this list, Commander) agree on what each session's
/// live tool / spend / context / branch should read. Rich enriched fields are
/// gated by Settings toggles so users can pare back what they see.
struct SessionRow: View {
    let snapshot: SessionSnapshot
    /// Pre-built by `DashboardView` from one shared 1 Hz tick — the row is a
    /// pure renderer (no own timer), matching `AgentCard` on the Commander board.
    let model: AgentCardModel
    let buckets: [SessionStatus?]
    @EnvironmentObject var settings: Settings

    var body: some View {
        content(model)
    }

    private func content(_ model: AgentCardModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StaticStatusIcon(status: snapshot.status, size: 22, dim: !snapshot.isAlive)
                .frame(width: 24)
                .padding(.top, 4)
                .overlay(alignment: .bottomTrailing) {
                    if model.hasRecentError {
                        Circle().fill(.red).frame(width: 5, height: 5)
                            .overlay(Circle().stroke(Color(NSColor.controlBackgroundColor), lineWidth: 0.5))
                            .offset(x: 2, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                titleRow(model)
                secondaryLine(model)
                metaChips(model)
                SparklineView(buckets: buckets, height: 12)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.uptime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("pid \(snapshot.pid)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .opacity(snapshot.isAlive ? 1.0 : 0.45)
        .help(tooltip)
    }

    // MARK: - Title row

    private func titleRow(_ model: AgentCardModel) -> some View {
        HStack(spacing: 6) {
            Text(displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if showTitleSubtext {
                Text(snapshot.cwdBasename)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let branch = model.branch {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                    Text(branch).font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            }
            if snapshot.providerId != "claude-code" {
                Text(snapshot.providerId)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.18), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayTitle: String {
        if settings.showAITitleAndLastPrompt, let t = snapshot.enriched?.aiTitle, !t.isEmpty {
            return t
        }
        return snapshot.fallbackTitle
    }

    /// Show the cwd as a small subtext only when we have an AI title (so the
    /// repo name isn't lost) and it actually adds information — not when the AI
    /// title already equals the repo basename.
    private var showTitleSubtext: Bool {
        guard settings.showAITitleAndLastPrompt,
              let t = snapshot.enriched?.aiTitle, !t.isEmpty else { return false }
        return t != snapshot.cwdBasename
    }

    // MARK: - Secondary line (live tool > waiting > status word)

    @ViewBuilder
    private func secondaryLine(_ model: AgentCardModel) -> some View {
        if !model.activity.isEmpty {
            // Busy/running with a tool in flight, or waiting on an approval —
            // show the live action + elapsed instead of just the status word.
            HStack(spacing: 5) {
                Image(systemName: model.isWaiting ? "bell.badge.fill" : "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(model.isWaiting ? .orange : .blue)
                Text(model.activity)
                    .font(.caption)
                    .foregroundStyle(model.isWaiting ? .orange : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !model.activityElapsed.isEmpty {
                    Text(model.activityElapsed)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        } else {
            Text(statusText(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func statusText(_ model: AgentCardModel) -> String {
        var text = snapshot.status.displayName
        if let w = snapshot.waitingFor, !w.isEmpty {
            text += " — \(w)"
        } else if !model.idleFor.isEmpty {
            // "Idle · 14m" / "Error · 14m" — how long it's been sitting.
            text += " · \(model.idleFor)"
        }
        return text
    }

    // MARK: - Meta chips

    @ViewBuilder
    private func metaChips(_ model: AgentCardModel) -> some View {
        let chips = computedChips(model)
        if !chips.isEmpty {
            HStack(spacing: 4) {
                ForEach(chips) { chip in
                    Text(chip.text)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(chip.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(chip.color)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private struct Chip: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let color: Color
    }

    private func computedChips(_ model: AgentCardModel) -> [Chip] {
        var out: [Chip] = []
        if settings.showPermissionMode, let mode = model.permissionMode, mode != "default" {
            out.append(Chip(text: mode, color: modeColor(mode)))
        }
        if settings.showTokensAndCost, !model.tokens.isEmpty {
            let cost = model.cost.isEmpty ? "" : " · \(model.cost)"
            out.append(Chip(text: model.tokens + cost, color: .secondary))
        }
        if model.contextTokens > 0 {
            out.append(Chip(text: "\(Int((model.contextFraction * 100).rounded()))% ctx",
                            color: contextColor(model.contextFraction)))
        }
        if settings.showTaskList, model.hasTasks {
            out.append(Chip(text: "✓ \(model.tasksCompleted)/\(model.tasksTotal)", color: .blue))
        }
        return out
    }

    /// bypass is a safety signal (red); plan won't write (purple-ish blue);
    /// auto runs tools unattended (orange).
    private func modeColor(_ mode: String) -> Color {
        switch mode {
        case "bypass": .red
        case "auto":   .orange
        case "plan":   .blue
        default:       .secondary
        }
    }

    /// Context fill severity — matches the Commander gauge thresholds.
    private func contextColor(_ frac: Double) -> Color {
        frac > 0.85 ? .red : (frac > 0.6 ? .orange : .cyan)
    }

    // MARK: - Tooltip

    private var tooltip: String {
        var parts: [String] = []
        parts.append(snapshot.cwd.path)
        if let b = snapshot.enriched?.gitBranch { parts.append("branch: \(b)") }
        if let v = snapshot.version { parts.append("v\(v)") }
        if let k = snapshot.kind { parts.append(k) }
        if let w = snapshot.waitingFor { parts.append("waiting for: \(w)") }
        if let e = snapshot.enriched {
            if let m = e.currentModel { parts.append("model: \(m)") }
            if e.contextTokens > 0 {
                let limit = ContextWindow.limit(for: e.currentModel)
                let pct = Int((Double(e.contextTokens) / Double(limit) * 100).rounded())
                parts.append("context: \(TokenUsage.compact(e.contextTokens))/\(TokenUsage.compact(limit)) (\(pct)%)")
            }
            if let p = e.lastUserPrompt { parts.append("last prompt: \(p.prefix(120))") }
            if let t = e.lastAssistantText { parts.append("last reply: \(t.prefix(120))") }
        }
        return parts.joined(separator: "\n")
    }
}
