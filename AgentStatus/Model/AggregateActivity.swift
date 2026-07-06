import Foundation

/// Pure, `Equatable` view-model for the aggregate menu-bar item — a live activity
/// monitor. Collapses every live session into the single most important thing
/// worth showing in the menu bar, following the dashboard's priority: something
/// that **needs you** first, else what's actively **working**, else a calm
/// **idle** count. Empty when nothing is live.
///
/// All formatting decisions live here (unit-tested with a pinned `now`);
/// `AggregateMenuBarLabel` is a thin renderer. `Equatable` so the menu-bar label
/// only redraws on a genuine state change, not on every 1.3 Hz ingest.
struct AggregateActivity: Equatable {
    enum Mode: Equatable { case empty, idle, working, needsYou }

    let mode: Mode
    /// Drives the leading `StaticStatusIcon` (glyph + color).
    let iconStatus: SessionStatus
    /// Live session count — the fleet size. Surfaced as the badge (when > 1) and
    /// always in the accessibility label, so background sessions never vanish
    /// just because one session is the headline subject.
    let total: Int
    /// Count chip shown right after the icon, or nil to hide. Present when there
    /// are other live sessions to be aware of (`total > 1`), except in the
    /// multi-needs-you state whose own text ("3 need you") already carries a count.
    let badge: String?
    /// Main activity text, ready to tail-truncate. Empty in idle/empty (icon +
    /// count say it all).
    let text: String
    /// Needs-you states tint the icon/badge and get a subtle pill so they pop.
    let urgent: Bool

    /// Snapshots + `now` → the one line to show. Pure. `now` anchors elapsed
    /// (production passes a per-second `TimelineView` date; tests pin it).
    static func make(from snapshots: [SessionSnapshot], now: Date) -> AggregateActivity {
        let live = snapshots.filter { $0.isAlive }
        guard !live.isEmpty else {
            return AggregateActivity(mode: .empty, iconStatus: .idle, total: 0,
                                     badge: nil, text: "", urgent: false)
        }
        let total = live.count
        // Show the fleet size only when there's more than one session — a bare
        // "1" is noise.
        let fleetBadge = total > 1 ? "\(total)" : nil

        // 1. Needs you — waiting or errored — always wins: it's what you must act on.
        let needs = live.filter { $0.status == .waiting || $0.status == .error }
        if !needs.isEmpty {
            if needs.count == 1 {
                return AggregateActivity(mode: .needsYou, iconStatus: needs[0].status,
                                         total: total, badge: fleetBadge,
                                         text: needsYouText(needs[0]), urgent: true)
            }
            // Multiple: the text carries the alert count; lead with the most urgent
            // icon (error outranks waiting).
            let icon: SessionStatus = needs.contains { $0.status == .error } ? .error : .waiting
            return AggregateActivity(mode: .needsYou, iconStatus: icon, total: total,
                                     badge: nil, text: "\(needs.count) need you", urgent: true)
        }

        // 2. Working — busy/running — show the session with the freshest activity.
        // Freshness is measured by the most recently *started* active tool, which
        // lives in `coreEqual` (so a change republishes the label). `updatedAt` is
        // deliberately NOT used: `SessionStore.uiEqual` ignores it, so keying on it
        // would let the label show a stale lead.
        let working = live.filter { $0.status == .busy || $0.status == .running }
        if !working.isEmpty {
            let lead = working.max(by: { latestToolStart($0) < latestToolStart($1) }) ?? working[0]
            return AggregateActivity(mode: .working, iconStatus: .busy, total: total,
                                     badge: fleetBadge, text: workingText(lead, now: now), urgent: false)
        }

        // 3. Idle — live but nothing running. Use the dominant status icon (not a
        // hardcoded idle dot) so an alive paused/stopped/unknown session keeps its
        // own glyph instead of masquerading as healthy-idle.
        let icon = live.max(by: { $0.status.precedence < $1.status.precedence })?.status ?? .idle
        return AggregateActivity(mode: .idle, iconStatus: icon, total: total,
                                 badge: fleetBadge, text: "", urgent: false)
    }

    /// The most recent `startedAt` among a session's active tools (its freshest
    /// activity), or `.distantPast` when it's between tools.
    private static func latestToolStart(_ snap: SessionSnapshot) -> Date {
        snap.enriched?.activeTools.map(\.startedAt).max() ?? .distantPast
    }

    // MARK: - Text composition

    /// What a needs-you session is asking for. Waiting → the approval target
    /// (mirrors the per-session row); error → the failed tool.
    private static func needsYouText(_ snap: SessionSnapshot) -> String {
        if snap.status == .error {
            if let failed = (snap.enriched?.recentTools ?? []).first(where: { $0.isError }) {
                return "\(failed.name) failed"
            }
            return "error"
        }
        // Waiting: activeTools is sorted ascending by startedAt, so `.last` is the
        // pending approval target.
        if let pending = snap.enriched?.activeTools.last {
            let preview = pending.preview.trimmingCharacters(in: .whitespaces)
            return preview.isEmpty ? "approve \(pending.name)" : "approve \(pending.name) · \(preview)"
        }
        return "needs input"
    }

    /// The lead working session's live action: its running tool + preview + a
    /// minute-granularity elapsed (a per-second `TimelineView` in the label keeps
    /// this advancing). Falls back to what it's working on when between tools.
    private static func workingText(_ snap: SessionSnapshot, now: Date) -> String {
        // activeTools is sorted ascending by startedAt → `.first` is the earliest,
        // the natural elapsed anchor.
        if let first = snap.enriched?.activeTools.first {
            let elapsed = max(0, now.timeIntervalSince(first.startedAt))
            let preview = first.preview.trimmingCharacters(in: .whitespaces)
            let head = preview.isEmpty ? first.name : "\(first.name) · \(preview)"
            return head + ElapsedFormatter.minuteSuffix(elapsed)
        }
        if let title = snap.enriched?.aiTitle, !title.isEmpty { return title }
        return "working"
    }
}
