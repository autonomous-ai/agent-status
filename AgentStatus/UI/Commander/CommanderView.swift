import SwiftUI
import AppKit

/// Fullscreen "commander" board — a dark control-room view of every session.
/// Read-only. Sessions are bold, status-colored cards grouped by urgency, so
/// blocked/errored agents glow loud at the top and idle ones recede. Click a
/// card to reveal full detail inline (no modal). Hosted by
/// `CommanderWindowController`.
struct CommanderView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: Settings
    @State private var selected: String?

    private let minCardWidth: CGFloat = 360
    private let cardSpacing: CGFloat = 16

    var body: some View {
        // One shared 1 Hz tick drives every card's elapsed/activity and the
        // in-flight timers in the expanded detail — no per-card timers.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack {
                canvas
                VStack(spacing: 0) {
                    ribbon(now: ctx.date)
                    Divider().overlay(Color.white.opacity(0.06))
                    content(now: ctx.date)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .preferredColorScheme(.dark)
    }

    private var canvas: some View {
        LinearGradient(
            colors: [Color(red: 0.09, green: 0.10, blue: 0.13),
                     Color(red: 0.04, green: 0.04, blue: 0.06)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Command ribbon

    private func ribbon(now: Date) -> some View {
        let totals = Totals(store.snapshots)
        return HStack(alignment: .center, spacing: 18) {
            StatusRingIcon(status: store.aggregate.dominant, size: 30)
                .opacity(store.aggregate.total == 0 ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text("Commander").font(.system(size: 22, weight: .bold))
                Text(liveSummary).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            statTiles
            Divider().frame(height: 34).overlay(Color.white.opacity(0.12))
            metric(totals.activeTools > 0 ? "\(totals.activeTools)" : "0", "tools", "bolt.fill", .blue)
            metric(totals.tokens.isEmpty ? "0" : totals.tokens, "tokens", "number", .secondary)
            metric(totals.cost.isEmpty ? "$0" : totals.cost, "spend", "dollarsign.circle.fill", .green)
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help("Toggle fullscreen")
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var liveSummary: String {
        let live = store.snapshots.filter { $0.isAlive }.count
        switch live {
        case 0: return "No live sessions"
        case 1: return "1 live session"
        default: return "\(live) live sessions"
        }
    }

    /// Big colored counters for the urgent states, only when non-zero.
    @ViewBuilder
    private var statTiles: some View {
        let order: [SessionStatus] = [.error, .waiting, .busy, .idle]
        HStack(spacing: 10) {
            ForEach(order, id: \.self) { st in
                if let n = store.aggregate.counts[st], n > 0 {
                    HStack(spacing: 7) {
                        Circle().fill(st.color).frame(width: 10, height: 10)
                            .shadow(color: st.color.opacity(0.8), radius: 3)
                        Text("\(n)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(st.displayName.lowercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(st.color.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(st.color.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Grouped card grid

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.snapshots.isEmpty {
            emptyState
        } else {
            GeometryReader { geo in
                let columns = max(1, Int((geo.size.width - 48 + cardSpacing) / (minCardWidth + cardSpacing)))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                        ForEach(CommanderGroup.allCases, id: \.self) { group in
                            let snaps = snapshots(in: group)
                            if !snaps.isEmpty {
                                Section {
                                    grid(snaps, columns: columns, now: now)
                                        .padding(.horizontal, 24)
                                } header: {
                                    groupHeader(group, count: snaps.count)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }

    /// Manual rows of `columns` cards. After the row containing the selected
    /// card, a full-width detail panel is inserted (so its multi-column layout
    /// fits) — that's why we don't use a plain LazyVGrid here.
    @ViewBuilder
    private func grid(_ snaps: [SessionSnapshot], columns: Int, now: Date) -> some View {
        let rows = stride(from: 0, to: snaps.count, by: columns).map { start in
            Array(snaps[start..<min(start + columns, snaps.count)])
        }
        VStack(spacing: cardSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowSnaps in
                HStack(spacing: cardSpacing) {
                    ForEach(rowSnaps) { snap in
                        AgentCard(
                            model: AgentCardModel.make(from: snap, now: now),
                            buckets: store.history(for: snap.id).bucket(into: 60, span: 60),
                            isSelected: selected == snap.id,
                            onTap: { toggle(snap.id) }
                        )
                    }
                    // Pad the last short row so cards keep their column width.
                    if rowSnaps.count < columns {
                        ForEach(0..<(columns - rowSnaps.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                if let sel = selected, rowSnaps.contains(where: { $0.id == sel }) {
                    CommanderDetailStrip(snapshotId: sel, now: now)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private func groupHeader(_ group: CommanderGroup, count: Int) -> some View {
        let tint = headerTint(group)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 18)
            Text(group.title.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
                .tracking(1.2)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(tint.opacity(0.22), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func headerTint(_ group: CommanderGroup) -> Color {
        switch group {
        case .needsYou: .orange
        case .working:  .blue
        case .idle:     .green
        case .ended:    .secondary
        }
    }

    private func snapshots(in group: CommanderGroup) -> [SessionSnapshot] {
        store.snapshots.filter { AgentCardModel.group(for: $0) == group }
    }

    private func toggle(_ id: String) {
        selected = (selected == id) ? nil : id
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 52)).foregroundStyle(.tertiary)
            Text("No Claude Code sessions running")
                .font(.title2.weight(.medium)).foregroundStyle(.secondary)
            Text("Open a Claude Code instance and it will appear here.")
                .font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Cross-session rollups for the ribbon — Σ in-flight tools, tokens, cost.
private struct Totals {
    let activeTools: Int
    let tokens: String
    let cost: String

    init(_ snapshots: [SessionSnapshot]) {
        let live = snapshots.filter { $0.isAlive }
        activeTools = live.reduce(0) { $0 + ($1.enriched?.activeTools.count ?? 0) }
        let tok = live.reduce(0) { $0 + ($1.enriched?.tokens.grandTotal ?? 0) }
        let usd = live.reduce(0.0) { $0 + ($1.enriched?.estimatedCost ?? 0) }
        tokens = tok > 0 ? TokenUsage.compact(tok) : ""
        cost = usd > 0 ? usd.asUSD : ""
    }
}
