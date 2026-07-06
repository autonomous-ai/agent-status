import SwiftUI

@main
struct AgentStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(env.store)
                .environmentObject(env.settings)
                .environmentObject(env.commander)
        } label: {
            // Wrap in a small observable view so the label re-renders when
            // store.aggregate publishes. Reading env.store.aggregate inline
            // would capture a stale snapshot — App's body only re-evaluates
            // on env's own objectWillChange, not the nested store's.
            MenuBarLabelView(store: env.store)
                .task {
                    // Boot from the always-present label task (not just the
                    // dropdown content's `.task`, which doesn't run until the
                    // user first opens the popover) so the menu bar reflects live
                    // sessions immediately. `boot()` is idempotent.
                    await env.boot()

                    // Dev/verification affordance: `open AgentStatus.app --args
                    // --commander` opens the Commander board immediately, without
                    // clicking through the menu bar.
                    if CommandLine.arguments.contains("--commander") {
                        env.commander.show()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        // `now: Date()` is sampled per render; the label re-renders on every store
        // republish (tool/status/token changes all flow through `coreEqual`), so
        // the activity line stays current. We deliberately do NOT drive this with a
        // TimelineView: a periodic timeline in a MenuBarExtra *label* hangs the app
        // at launch, and the codebase intentionally keeps timers off the menu bar
        // (see StaticStatusIcon). Trade-off: the minute-granularity elapsed only
        // advances on a republish — frequent during active work, but a lone
        // multi-minute tool with no other change can show a stale suffix.
        AggregateMenuBarLabel(activity: AggregateActivity.make(from: store.snapshots, now: Date()))
    }
}
