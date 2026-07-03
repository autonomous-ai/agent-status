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
                .task { await env.boot() }
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
        // `now: Date()` is captured per render; the label re-renders whenever the
        // store republishes (tool/status/token changes all flow through
        // `coreEqual`), so the activity line stays current without a timer.
        AggregateMenuBarLabel(activity: AggregateActivity.make(from: store.snapshots, now: Date()))
    }
}
