import Foundation

/// Which urgency band a session belongs to on the Commander board. Drives the
/// grouped sections so blocked/errored agents pin to the top and idle ones
/// recede — the product's "do I need to look at this session?" triage, made
/// spatial. Raw value is the sort/precedence order (lower = more urgent).
enum CommanderGroup: Int, CaseIterable, Hashable {
    case needsYou = 0   // waiting or error — a human action item
    case working  = 1   // busy / running
    case idle     = 2   // alive but resting (idle / paused / stopped / unknown)
    case ended    = 3   // process gone

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working:  "Working"
        case .idle:     "Idle"
        case .ended:    "Ended"
        }
    }
}

/// Pure, testable view-model for one Commander agent card. Derives every display
/// string from a `SessionSnapshot` at a given `now`, so `AgentCard` stays a thin
/// renderer and the formatting is unit-testable — the same split as
/// `PerSessionStatusItem.rowData(from:now:)` for the menu-bar row.
struct AgentCardModel: Equatable {
    let id: String
    let group: CommanderGroup
    let status: SessionStatus
    let statusLabel: String
    let title: String
    let subtitle: String          // cwd basename (the repo)
    let uptime: String            // session age, e.g. "5m 12s"

    // Activity (the hero column)
    let activity: String          // current tool / approval line; "" when idle
    let activityElapsed: String   // age of the active/pending tool; "" when none
    let isWaiting: Bool           // tints the activity orange vs blue
    let activeToolCount: Int      // drives concurrency dots
    let dim: Bool                 // session no longer alive
    let hasRecentError: Bool      // any of the last 5 completed tools errored

    // Thinking (busy/running with no tool in flight — the model is generating).
    // Instead of a bare "Thinking…", surface the last thing it did and how long
    // it's been generating since — a quick vs stuck signal.
    let lastAction: String?       // most recent completed tool, e.g. "Edit · SKILL.md"; nil if none yet
    let thinkingElapsed: String   // time since that last action; "" if no anchor

    // Task list
    let taskHeadline: String?     // "▸ Rewriting parser" (in-progress, else next pending)
    let tasksCompleted: Int
    let tasksTotal: Int

    // Spend / context
    let tokens: String            // compact grand total; "" when zero
    let cost: String              // asUSD; "" when zero/unknown
    let model: String?            // short model id (sans "claude-")
    let permissionMode: String?   // "plan" / "auto" / "bypass" / …
    let branch: String?           // git branch the session is on
    let contextTokens: Int        // live context size at last API call
    let contextLimit: Int         // model's context window
    let idleFor: String           // how long a resting session has been idle; "" if <1m or not resting

    // Autonomy
    let goal: String?             // active /goal condition the session is working toward; nil if none
    let goalAchieved: Bool        // the /goal condition was met — show a green "achieved" state, not the active banner
    let goalSummary: String?      // "12m · 1 turn · 53.2k" run summary; nil unless achieved
    let loop: String?             // best-effort /loop target ("5m /foo" / "self-paced"); nil if not looping

    var hasTasks: Bool { tasksTotal > 0 }
    var taskFraction: Double { tasksTotal == 0 ? 0 : Double(tasksCompleted) / Double(tasksTotal) }
    var contextFraction: Double {
        contextLimit == 0 ? 0 : min(1, Double(contextTokens) / Double(contextLimit))
    }

    static func make(from snap: SessionSnapshot, now: Date) -> AgentCardModel {
        let e = snap.enriched

        let title: String = {
            if let t = e?.aiTitle, !t.isEmpty { return t }
            return snap.fallbackTitle
        }()

        let (activity, anchor, isWaiting) = activityLine(for: snap)
        let activityElapsed = anchor.map { ElapsedFormatter.short(from: $0, to: now) } ?? ""

        // Most recent completed tool — the "just did X" hint shown while thinking.
        // recentTools is newest-first; its endedAt anchors the thinking timer.
        let lastCompleted = (e?.recentTools ?? []).first
        let lastAction: String? = lastCompleted.map { t in
            let p = t.preview.trimmingCharacters(in: .whitespaces)
            return p.isEmpty ? t.name : "\(t.name) · \(p)"
        }
        let thinkingElapsed = lastCompleted.map { ElapsedFormatter.short(from: $0.endedAt, to: now) } ?? ""

        let live = (e?.todos ?? []).filter { $0.status != .deleted }
        let completed = live.filter { $0.status == .completed }.count
        let headline: String? = {
            guard !live.isEmpty else { return nil }
            if let ip = live.first(where: { $0.status == .inProgress }) {
                return "▸ \(ip.activeForm ?? ip.title)"
            }
            if let next = live.first(where: { $0.status == .pending }) {
                return "▸ \(next.title)"
            }
            return nil   // all tasks done — the k/n counter says it
        }()

        // Goal-achieved summary, mirroring the CLI's "Goal achieved (12m · 1 turn
        // · 53.2k tokens)". Presence of an outcome IS the achieved signal.
        let goalSummary: String? = e?.goalOutcome.map { o in
            let secs = o.durationMs / 1000
            let dur = secs >= 60 ? "\(secs / 60)m" : "\(secs)s"
            let turns = "\(o.iterations) turn" + (o.iterations == 1 ? "" : "s")
            return "\(dur) · \(turns) · \(TokenUsage.compact(o.tokens))"
        }

        let recentError = (e?.recentTools ?? []).prefix(5).contains { $0.isError }
        let grand = e?.tokens.grandTotal ?? 0
        let estCost = e?.estimatedCost ?? 0

        // "Idle 14m" / "Error for 14m" matters (is this session stalled?);
        // "30s" is churn. Quiet = alive with nothing in flight — busy/running
        // without a tool means the model is generating ("Thinking"), not quiet.
        let quiet: Bool = {
            guard snap.isAlive, activity.isEmpty else { return false }
            switch snap.status {
            case .busy, .running: return false
            default: return true
            }
        }()
        let idleFor: String = {
            guard quiet, now.timeIntervalSince(snap.updatedAt) >= 60 else { return "" }
            return ElapsedFormatter.short(from: snap.updatedAt, to: now)
        }()

        return AgentCardModel(
            id: snap.id,
            group: group(for: snap),
            status: snap.status,
            statusLabel: snap.status.displayName,
            title: title,
            subtitle: snap.cwdBasename,
            uptime: ElapsedFormatter.short(from: snap.startedAt, to: now),
            activity: activity,
            activityElapsed: activityElapsed,
            isWaiting: isWaiting,
            activeToolCount: e?.activeTools.count ?? 0,
            dim: !snap.isAlive,
            hasRecentError: recentError,
            lastAction: lastAction,
            thinkingElapsed: thinkingElapsed,
            taskHeadline: headline,
            tasksCompleted: completed,
            tasksTotal: live.count,
            tokens: grand > 0 ? TokenUsage.compact(grand) : "",
            cost: estCost > 0 ? estCost.asUSD : "",
            model: shortModel(e?.currentModel),
            permissionMode: shortMode(e?.permissionMode),
            branch: e?.gitBranch,
            contextTokens: e?.contextTokens ?? 0,
            contextLimit: ContextWindow.limit(for: e?.currentModel),
            idleFor: idleFor,
            goal: e?.goalCondition,
            goalAchieved: e?.goalOutcome != nil,
            goalSummary: goalSummary,
            loop: e?.loopTarget
        )
    }

    /// Urgency band. Grouped by live status only — `hasRecentError` shows a pip
    /// but doesn't re-bucket a recovered session (matches the menu bar, where a
    /// past error is a pip, not a status).
    static func group(for snap: SessionSnapshot) -> CommanderGroup {
        if !snap.isAlive { return .ended }
        switch snap.status {
        case .waiting, .error:   return .needsYou
        case .busy, .running:    return .working
        default:                 return .idle
        }
    }

    /// The activity description, the `Date` its elapsed time is measured against
    /// (the relevant tool's `startedAt`, or nil when idle), and whether it's a
    /// waiting/approval line. Mirrors `PerSessionStatusItem.bottomText` priorities.
    private static func activityLine(for snap: SessionSnapshot) -> (String, Date?, Bool) {
        let active = snap.enriched?.activeTools ?? []

        if snap.status == .waiting {
            // activeTools is sorted oldest-first, so `.last` is the approval target.
            if let pending = active.last {
                let p = pending.preview.trimmingCharacters(in: .whitespaces)
                let line = p.isEmpty ? "approve \(pending.name)" : "approve \(pending.name) · \(p)"
                return (line, pending.startedAt, true)
            }
            return ("", nil, true)
        }

        if (snap.status == .busy || snap.status == .running), !active.isEmpty {
            if active.count == 1 {
                let t = active[0]
                let p = t.preview.trimmingCharacters(in: .whitespaces)
                return (p.isEmpty ? t.name : "\(t.name) · \(p)", t.startedAt, false)
            }
            // Multi-tool: name the first two, "+N" the rest. The concurrency dots
            // already carry the exact count.
            let names = active.map(\.name)
            let visible = names.prefix(2).joined(separator: ", ")
            let overflow = names.count - 2
            let head = overflow > 0 ? "\(visible) +\(overflow)" : visible
            return (head, active[0].startedAt, false)
        }

        return ("", nil, false)
    }

    /// "claude-opus-4-8" → "opus-4-8"; leaves anything else untouched.
    private static func shortModel(_ model: String?) -> String? {
        guard let m = model, !m.isEmpty else { return nil }
        let prefix = "claude-"
        return m.hasPrefix(prefix) ? String(m.dropFirst(prefix.count)) : m
    }

    /// "bypassPermissions" → "bypass"; passes through "plan"/"auto"/"default".
    private static func shortMode(_ mode: String?) -> String? {
        guard let m = mode, !m.isEmpty else { return nil }
        return m == "bypassPermissions" ? "bypass" : m
    }
}
