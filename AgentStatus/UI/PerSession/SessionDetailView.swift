import SwiftUI
import AppKit

/// Per-session popover. Built lazily by `PerSessionStatusItem` so its timers only
/// run while on-screen. Leads with the **same `AgentCard`** the Commander board
/// uses — so the popover reads as one of those bold, status-tinted cards — then
/// adds a compact, card-idiom detail section (approval, extra tools, token split,
/// recent/tasks, prompts, metadata) below it.
struct SessionDetailView: View {
    let snapshotId: String

    var body: some View {
        // One shared 1 Hz tick drives the card's elapsed and the detail rows —
        // no per-section timers (matches the Commander board). The ScrollView
        // lives here (not in SessionDetailContent) so the content renders
        // headlessly for snapshot tests — ImageRenderer can't lay out a ScrollView.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ScrollView {
                SessionDetailContent(snapshotId: snapshotId, now: ctx.date)
            }
            .frame(width: 380, height: 470)
        }
    }
}

/// Pure content of the popover for a pinned `now` (production passes the
/// `TimelineView` date; tests pin it). A thin composition over `AgentCard` +
/// detail sections so it renders headlessly for snapshot review.
struct SessionDetailContent: View {
    let snapshotId: String
    let now: Date
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        let snap = store.snapshots.first { $0.id == snapshotId }
        return VStack(alignment: .leading, spacing: 12) {
            if let s = snap {
                    // The card — identical to the Commander board tile, so the two
                    // surfaces share one visual language (and one component).
                    AgentCard(
                        model: AgentCardModel.make(from: s, now: now),
                        spend: store.history(for: s.id).tokenSeries(into: 60, span: 60, now: now),
                        isSelected: false,
                        onTap: {}
                    )

                    if s.status == .waiting { waitingSection(for: s) }

                    // The card's hero shows the primary tool; list the rest here.
                    if let active = s.enriched?.activeTools, active.count > 1 {
                        runningNowSection(Array(active))
                    }

                    if settings.showTaskList, let todos = s.enriched?.todos, !todos.isEmpty {
                        todosSection(todos)
                    } else {
                        recentToolsSection(for: s)
                    }

                    if settings.showTokensAndCost, let e = s.enriched, e.tokens.grandTotal > 0 {
                        tokenSplitSection(e)
                    }

                    if settings.showAITitleAndLastPrompt { promptsSection(s.enriched) }

                    metadataSection(for: s)
                    actions(for: s)
            } else {
                Text("Session is no longer running.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section chrome

    /// Bold small-caps section label — the card idiom, replacing the old gray
    /// `.caption2` headers.
    private func sectionLabel(_ text: String, tint: Color = .secondary) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(tint)
            .tracking(0.8)
    }

    /// A detail block: a subtle rounded surface so each group reads as a distinct
    /// card-like panel rather than a divider-separated table row.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
    }

    // MARK: - Waiting

    @ViewBuilder
    private func waitingSection(for s: SessionSnapshot) -> some View {
        let pending = s.enriched?.activeTools.last
        let pendingInput: [String: Any]? = pending?.rawInputJSON.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        if let display = TranscriptTailer.waitingDisplay(
            for: s.waitingFor, pending: pending, pendingInput: pendingInput
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                    Text(headlineLabel(for: display))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                detailLines(for: display)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func headlineLabel(for d: WaitingDisplay) -> String {
        switch d {
        case .tool(let name, _):  "Waiting · approve \(name)"
        case .askUserQuestion:    "Waiting · approve AskUserQuestion"
        case .subagent:           "Waiting · approve Task"
        case .unknown(let raw):   "Waiting · \(raw)"
        }
    }

    @ViewBuilder
    private func detailLines(for d: WaitingDisplay) -> some View {
        switch d {
        case .tool(_, let preview):
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
        case .askUserQuestion(let text, let options):
            VStack(alignment: .leading, spacing: 3) {
                if !text.isEmpty {
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                ForEach(Array(options.prefix(4).enumerated()), id: \.offset) { idx, label in
                    Text("  \(idx + 1). \(label)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        case .subagent(let description, let prompt):
            VStack(alignment: .leading, spacing: 3) {
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !prompt.isEmpty {
                    Text(prompt.count > 100 ? String(prompt.prefix(100)) + "\u{2026}" : prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Running now (the tools beyond the card's hero)

    private func runningNowSection(_ active: [ActiveTool]) -> some View {
        let visible = Array(active.prefix(5))
        let overflow = active.count - visible.count
        return panel {
            sectionLabel("Running now (\(active.count))", tint: .blue)
            ForEach(visible, id: \.id) { tool in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.blue)
                    Text(tool.name).font(.system(size: 11, weight: .medium))
                    if !tool.preview.isEmpty {
                        Text(tool.preview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer()
                    Text(elapsed(from: tool.startedAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if overflow > 0 {
                Text("+\(overflow) more\u{2026}").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func elapsed(from start: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m\(secs % 60)s"
    }

    // MARK: - Recent tools

    @ViewBuilder
    private func recentToolsSection(for s: SessionSnapshot) -> some View {
        let recent = s.enriched?.recentTools ?? []
        if !recent.isEmpty {
            panel {
                sectionLabel("Recent (\(recent.count))")
                ForEach(recent, id: \.id) { tool in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: tool.isError ? "xmark" : "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tool.isError ? .red : .green)
                        Text(tool.name).font(.system(size: 11, weight: .medium))
                        if !tool.preview.isEmpty {
                            Text(tool.preview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        Spacer()
                        Text(formatDuration(tool.duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(tool.isError ? .red.opacity(0.8) : .secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 60 { return String(format: "%.1fs", d) }
        return "\(Int(d) / 60)m\(Int(d) % 60)s"
    }

    // MARK: - Tasks

    private func todosSection(_ todos: [TodoItem]) -> some View {
        let rows = TodoDisplay.rows(from: todos)
        return panel {
            sectionLabel("Tasks (\(rows.completedCount)/\(rows.totalCount))", tint: .blue)
            ForEach(rows.visible, id: \.id) { todoRow($0) }
            if rows.hiddenCompletedCount > 0 {
                Text("\u{2026} +\(rows.hiddenCompletedCount) completed")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 18)
            }
        }
    }

    private func todoRow(_ item: TodoItem) -> some View {
        let done = item.status == .completed
        let inProgress = item.status == .inProgress
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: todoSymbol(item.status))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(todoColor(item.status))
                .frame(width: 12, alignment: .center)
            Text(inProgress ? (item.activeForm ?? item.title) : item.title)
                .font(.system(size: 11, weight: inProgress ? .semibold : .regular))
                .foregroundStyle(done ? .secondary : .primary)
                .strikethrough(done, color: .secondary)
                .lineLimit(2).truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func todoSymbol(_ status: TodoStatus) -> String {
        switch status {
        case .inProgress: "circle.lefthalf.filled"
        case .completed:  "checkmark.square.fill"
        default:          "square"
        }
    }

    private func todoColor(_ status: TodoStatus) -> Color {
        switch status {
        case .inProgress: .blue
        case .completed:  .green
        default:          .secondary
        }
    }

    // MARK: - Token split (card shows the total/cost/context; this is the breakdown)

    private func tokenSplitSection(_ e: EnrichedSession) -> some View {
        panel {
            sectionLabel("Token breakdown")
            HStack(spacing: 16) {
                tokenStat("in", e.tokens.input)
                tokenStat("out", e.tokens.output)
                tokenStat("cache r", e.tokens.cacheRead)
                tokenStat("cache w", e.tokens.cacheCreation)
                Spacer(minLength: 0)
            }
        }
    }

    private func tokenStat(_ label: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            Text(TokenUsage.compact(n))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    // MARK: - Prompts

    @ViewBuilder
    private func promptsSection(_ e: EnrichedSession?) -> some View {
        let hasPrompt = !(e?.lastUserPrompt ?? "").isEmpty
        let hasReply = !(e?.lastAssistantText ?? "").isEmpty
        if hasPrompt || hasReply {
            panel {
                if let p = e?.lastUserPrompt, !p.isEmpty {
                    sectionLabel("Last prompt")
                    Text(p).font(.caption).lineLimit(3).truncationMode(.tail).textSelection(.enabled)
                }
                if let r = e?.lastAssistantText, !r.isEmpty {
                    sectionLabel("Last reply").padding(.top, hasPrompt ? 4 : 0)
                    Text(r).font(.caption).lineLimit(3).truncationMode(.tail).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Metadata

    private func metadataSection(for s: SessionSnapshot) -> some View {
        panel {
            sectionLabel("Details")
            row("path", s.cwd.path, monospaced: true)
            if let b = s.enriched?.gitBranch { row("branch", b, monospaced: true) }
            if settings.showPermissionMode, let m = s.enriched?.permissionMode { row("mode", m) }
            if let n = s.enriched?.subagentName { row("agent", n) }
            if let v = s.version { row("version", v) }
            if let k = s.kind { row("kind", k) }
            if let e = s.enriched, e.assistantTurns > 0 { row("turns", "\(e.assistantTurns)") }
            if let e = s.enriched, e.toolCalls > 0 {
                row("tools", "\(e.toolCalls) calls\(e.errorCount > 0 ? " · \(e.errorCount) errors" : "")")
            }
            row("pid", "\(s.pid)", monospaced: true)
        }
    }

    private func row(_ key: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .trailing)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func actions(for s: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([s.cwd])
            }
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(s.pid)", forType: .string)
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .font(.caption)
    }
}
