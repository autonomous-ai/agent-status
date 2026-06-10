import Foundation

/// DI container constructed once at app launch, held by AgentStatusApp as @StateObject.
/// All dependents read these via .environmentObject in SwiftUI or by direct injection in
/// imperative AppKit controllers.
@MainActor
final class AppEnvironment: ObservableObject {
    let registry: ProviderRegistry
    let store: SessionStore
    let settings: Settings
    let perSessionItems: PerSessionItemController
    let notifications: NotificationManager
    let commander: CommanderWindowController

    init() {
        let registry = ProviderRegistry()
        registry.register(ClaudeCodeProvider())
        registry.register(CodexProvider())
        self.registry = registry
        let store = SessionStore(registry: registry)
        let settings = Settings()
        self.store = store
        self.settings = settings
        self.perSessionItems = PerSessionItemController(store: store, settings: settings)
        self.notifications = NotificationManager(store: store, settings: settings)
        self.commander = CommanderWindowController(store: store, settings: settings)
    }

    private var booted = false

    /// Idempotent: callable from both the menu-bar popover's `.task` and the
    /// `--commander` launch hook without double-subscribing notifications.
    func boot() async {
        guard !booted else { return }
        booted = true
        await store.start()
        notifications.start()
    }
}
