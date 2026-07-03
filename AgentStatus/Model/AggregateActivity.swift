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
    /// Small count chip shown right after the icon: "3" working, "5" idle,
    /// "2" needing you. Nil when a single-subject line carries its own detail.
    let badge: String?
    /// Main activity text, already composed and ready to tail-truncate. Empty in
    /// the empty state (icon alone).
    let text: String
    /// Needs-you states tint the icon/badge and get a subtle pill so they pop.
    let urgent: Bool

    /// Snapshots + `now` → the one line to show. Pure. `now` anchors elapsed
    /// (production passes `Date()`; tests pin it).
    static func make(from snapshots: [SessionSnapshot], now: Date) -> AggregateActivity {
        let live = snapshots.filter { $0.isAlive }
        guard !live.isEmpty else {
            return AggregateActivity(mode: .empty, iconStatus: .idle, badge: nil, text: "", urgent: false)
        }

        // 1. Needs you — waiting or errored — always wins: it's the thing you must act on.
        let needs = live.filter { $0.status == .waiting || $0.status == .error }
        if !needs.isEmpty {
            if needs.count == 1 {
                return AggregateActivity(mode: .needsYou, iconStatus: needs[0].status,
                                         badge: nil, text: needsYouText(needs[0]), urgent: true)
            }
            // Multiple: lead with the most urgent icon (error outranks waiting).
            let icon: SessionStatus = needs.contains { $0.status == .error } ? .error : .waiting
            return AggregateActivity(mode: .needsYou, iconStatus: icon,
                                     badge: "\(needs.count)", text: "need you", urgent: true)
        }

        // 2. Working — busy/running — show the freshest session's live activity.
        let working = live.filter { $0.status == .busy || $0.status == .running }
        if !working.isEmpty {
            let lead = working.max(by: { $0.updatedAt < $1.updatedAt }) ?? working[0]
            let badge = working.count > 1 ? "\(working.count)" : nil
            return AggregateActivity(mode: .working, iconStatus: .busy,
                                     badge: badge, text: workingText(lead, now: now), urgent: false)
        }

        // 3. Idle — live but nothing running: a calm count.
        return AggregateActivity(mode: .idle, iconStatus: .idle,
                                 badge: "\(live.count)", text: "", urgent: false)
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
    /// minute-granularity elapsed (no per-second timer, matching the per-session
    /// items). Falls back to what it's working on when between tools (thinking).
    private static func workingText(_ snap: SessionSnapshot, now: Date) -> String {
        // activeTools is sorted ascending by startedAt → `.first` is the earliest,
        // the natural elapsed anchor.
        if let first = snap.enriched?.activeTools.first {
            let elapsed = max(0, now.timeIntervalSince(first.startedAt))
            let suffix = elapsed >= 60 ? " · \(Int(elapsed) / 60)m" : ""
            let preview = first.preview.trimmingCharacters(in: .whitespaces)
            let head = preview.isEmpty ? first.name : "\(first.name) · \(preview)"
            return head + suffix
        }
        if let title = snap.enriched?.aiTitle, !title.isEmpty { return title }
        return "working"
    }
}
