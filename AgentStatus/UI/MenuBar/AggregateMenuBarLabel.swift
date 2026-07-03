import SwiftUI

/// Custom MenuBarExtra label: a compact **live-activity monitor**. Instead of a
/// lone dominant-status dot, it surfaces the single most important thing across
/// all live sessions — something that needs you, else what's actively working,
/// else a calm idle count — mirroring the dashboard. Driven by the pure
/// `AggregateActivity` view-model; no animations, so the menu bar stays calm.
struct AggregateMenuBarLabel: View {
    let activity: AggregateActivity

    var body: some View {
        HStack(spacing: 5) {
            icon
            if let badge = activity.badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            if !activity.text.isEmpty {
                Text(activity.text)
                    .font(.system(size: 12, weight: activity.urgent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(activity.urgent ? tint : .primary)
            }
        }
        .padding(.horizontal, activity.urgent ? 6 : 0)
        .padding(.vertical, activity.urgent ? 1 : 0)
        .background {
            if activity.urgent {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.16))
            }
        }
        // Width budget so a long tool preview can't push the clock off-screen;
        // the tail truncates, icon + badge always stay visible.
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Leading glyph. Empty state gets a legible hollow ring (the old
    /// `circle.dotted` hierarchical render was nearly invisible over a wallpaper);
    /// every other state reuses the animation-free `StaticStatusIcon`.
    @ViewBuilder private var icon: some View {
        switch activity.mode {
        case .empty:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        case .idle, .working, .needsYou:
            StaticStatusIcon(status: activity.iconStatus, size: 16)
        }
    }

    private var tint: Color { activity.iconStatus.color }

    private var accessibilityLabel: String {
        switch activity.mode {
        case .empty:    "Agent Status — no live sessions"
        case .idle:     "Agent Status — \(activity.badge ?? "0") idle"
        case .working:  "Agent Status — working: \(activity.text)"
        case .needsYou: "Agent Status — needs you: \(activity.text)"
        }
    }
}
