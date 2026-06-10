import SwiftUI
import AppKit

/// Full-width inline detail panel revealed when a Commander row is expanded.
/// Lays the same data the menu-bar popover shows, but across the window width in
/// columns (instead of a narrow 360px stack) — reusing the leaf views and data
/// derivations rather than `SessionDetailView`'s popover-shaped layout. `now`
/// comes from the board's shared 1 Hz timeline so in-flight elapsed ticks live.
struct CommanderDetailStrip: View {
    let snapshotId: String
    let now: Date

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        if let s = store.snapshots.first(where: { $0.id == snapshotId }) {
            VStack(alignment: .leading, spacing: 14) {
                if s.status == .waiting { waiting(for: s) }
                HStack(alignment: .top, spacing: 28) {
                    activityColumn(for: s).frame(maxWidth: .infinity, alignment: .leading)
                    tasksColumn(for: s).frame(maxWidth: .infinity, alignment: .leading)
                    contextColumn(for: s).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(Color.white.opacity(0.08))
                metadataAndActions(for: s)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(s.status.color.opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Waiting banner

    @ViewBuilder
    private func waiting(for s: SessionSnapshot) -> some View {
        let pending = s.enriched?.activeTools.last
        let input: [String: Any]? = pending?.rawInputJSON.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        if let display = TranscriptTailer.waitingDisplay(for: s.waitingFor, pending: pending, pendingInput: input) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                    Text("Waiting · \(waitingHeadline(display))")
                        .font(.subheadline.weight(.semibold))
                }
                waitingDetail(display)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func waitingHeadline(_ d: WaitingDisplay) -> String {
        switch d {
        case .tool(let name, _):  "approve \(name)"
        case .askUserQuestion:    "approve AskUserQuestion"
        case .subagent:           "approve Task"
        case .unknown(let raw):   raw
        }
    }

    @ViewBuilder
    private func waitingDetail(_ d: WaitingDisplay) -> some View {
        switch d {
        case .tool(_, let preview):
            if !preview.isEmpty {
                Text(preview).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        case .askUserQuestion(let text, let options):
            VStack(alignment: .leading, spacing: 2) {
                if !text.isEmpty { Text("“\(text)”").font(.system(size: 11)).foregroundStyle(.secondary) }
                ForEach(Array(options.prefix(4).enumerated()), id: \.offset) { i, label in
                    Text("  \(i + 1). \(label)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        case .subagent(let description, let prompt):
            VStack(alignment: .leading, spacing: 2) {
                if !description.isEmpty { Text(description).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                if !prompt.isEmpty {
                    Text(prompt.count > 160 ? String(prompt.prefix(160)) + "…" : prompt)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Activity column (running now + recent)

    @ViewBuilder
    private func activityColumn(for s: SessionSnapshot) -> some View {
        let active = s.enriched?.activeTools ?? []
        let recent = s.enriched?.recentTools ?? []
        VStack(alignment: .leading, spacing: 8) {
            if !active.isEmpty {
                sectionHeader("Running now (\(active.count))")
                ForEach(active, id: \.id) { t in
                    toolRow(icon: "bolt.fill", iconColor: s.status == .waiting ? .orange : .blue,
                            name: t.name, preview: t.preview, trailing: elapsed(from: t.startedAt))
                }
            }
            if !recent.isEmpty {
                sectionHeader("Recent (\(recent.count))")
                ForEach(recent, id: \.id) { t in
                    toolRow(icon: t.isError ? "xmark" : "checkmark",
                            iconColor: t.isError ? .red : .green,
                            name: t.name, preview: t.preview, trailing: duration(t.duration))
                }
            }
            if active.isEmpty && recent.isEmpty {
                Text("No tool activity yet").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func toolRow(icon: String, iconColor: Color, name: String, preview: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(iconColor).frame(width: 12)
            Text(name).font(.system(size: 11, weight: .medium))
            if !preview.isEmpty {
                Text(preview).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(trailing).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: - Tasks column

    @ViewBuilder
    private func tasksColumn(for s: SessionSnapshot) -> some View {
        let todos = s.enriched?.todos ?? []
        if settings.showTaskList, !todos.isEmpty {
            let rows = TodoDisplay.rows(from: todos, maxVisible: 12)
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("Tasks (\(rows.completedCount)/\(rows.totalCount))")
                ForEach(rows.visible, id: \.id) { todoRow($0) }
                if rows.hiddenCompletedCount > 0 {
                    Text("… +\(rows.hiddenCompletedCount) completed")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 18)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("Tasks")
                Text("No task list").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func todoRow(_ item: TodoItem) -> some View {
        let done = item.status == .completed
        let inProgress = item.status == .inProgress
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: todoSymbol(item.status))
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(todoColor(item.status)).frame(width: 12)
            Text(inProgress ? (item.activeForm ?? item.title) : item.title)
                .font(.system(size: 11, weight: inProgress ? .semibold : .regular))
                .foregroundStyle(done ? .secondary : .primary)
                .strikethrough(done, color: .secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func todoSymbol(_ s: TodoStatus) -> String {
        switch s {
        case .inProgress: "circle.lefthalf.filled"
        case .completed:  "checkmark.square.fill"
        default:          "square"
        }
    }

    private func todoColor(_ s: TodoStatus) -> Color {
        switch s {
        case .inProgress: .blue
        case .completed:  .green
        default:          .secondary
        }
    }

    // MARK: - Context column (tokens + prompts)

    @ViewBuilder
    private func contextColumn(for s: SessionSnapshot) -> some View {
        let e = s.enriched
        VStack(alignment: .leading, spacing: 8) {
            if settings.showTokensAndCost, let e, e.tokens.grandTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        sectionHeader("Tokens & cost")
                        Spacer()
                        if let m = e.currentModel { Text(m).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 12) {
                        tokenStat("in", e.tokens.input)
                        tokenStat("out", e.tokens.output)
                        tokenStat("c-rd", e.tokens.cacheRead)
                        tokenStat("c-wr", e.tokens.cacheCreation)
                        Spacer()
                        Text(e.estimatedCost.asUSD)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    }
                    if e.contextTokens > 0 {
                        contextRow(e)
                    }
                }
            }
            if settings.showAITitleAndLastPrompt {
                if let p = e?.lastUserPrompt, !p.isEmpty {
                    labeled("Last prompt", p)
                }
                if let r = e?.lastAssistantText, !r.isEmpty {
                    labeled("Last reply", r)
                }
            }
        }
    }

    /// Live context-window fill — exact numbers here, where there's room
    /// (the card carries the compact % gauge).
    private func contextRow(_ e: EnrichedSession) -> some View {
        let limit = ContextWindow.limit(for: e.currentModel)
        let frac = limit == 0 ? 0 : min(1.0, Double(e.contextTokens) / Double(limit))
        let tint: Color = frac > 0.85 ? .red : (frac > 0.6 ? .orange : .cyan)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(2, 120 * frac))
            }
            .frame(width: 120, height: 4)
            Text("context \(TokenUsage.compact(e.contextTokens)) / \(TokenUsage.compact(limit)) · \(Int((frac * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 2)
    }

    private func tokenStat(_ label: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            Text(TokenUsage.compact(n)).font(.system(size: 11, design: .monospaced)).monospacedDigit()
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader(label)
            Text(value).font(.caption).lineLimit(3).truncationMode(.tail).textSelection(.enabled)
        }
    }

    // MARK: - Metadata + actions

    private func metadataAndActions(for s: SessionSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            metaItem("path", s.cwd.path, mono: true)
            if let b = s.enriched?.gitBranch { metaItem("branch", b, mono: true) }
            if let v = s.version { metaItem("version", v) }
            if let k = s.kind { metaItem("kind", k) }
            metaItem("pid", "\(s.pid)", mono: true)
            if let e = s.enriched, e.assistantTurns > 0 {
                metaItem("turns", "\(e.assistantTurns)")
            }
            if let e = s.enriched, e.toolCalls > 0 {
                metaItem("tools", "\(e.toolCalls)\(e.errorCount > 0 ? " · \(e.errorCount) err" : "")")
            }
            Spacer()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.cwd]) }
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(s.pid)", forType: .string)
            }
        }
        .controlSize(.small)
        .font(.caption)
    }

    private func metaItem(_ key: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    // MARK: - Shared bits

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func elapsed(from start: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m\(secs % 60)s"
    }

    private func duration(_ d: TimeInterval) -> String {
        if d < 60 { return String(format: "%.1fs", d) }
        return "\(Int(d) / 60)m\(Int(d) % 60)s"
    }
}
