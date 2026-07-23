import SwiftUI
import AbbeyCompanionKit
import SwiftData

/// Root entry point for Abbey's native macOS companion app.
///
/// This app is a *companion* to Abbey Bot, not a reimplementation of it. It can run in
/// two modes, selected by `AppConfig.operatingMode`:
///   - `.standalone`  — everything (Brain, SocialBrain, EventBus) runs in-process against
///                      a local SwiftData store. Useful for on-device experimentation
///                      without a live Discord gateway connection.
///   - `.mirror`      — the app reads/writes the same conceptual schema the Vapor/Fluent
///                      bot uses, persisted locally via SwiftData rather than Postgres.
///                      Sync-to-Postgres is not implemented; use Dashboard JSON export/import
///                      for handoff. This app owns its own local store.
@main
struct AbbeyCompanionApp: App {
    @State private var engine: AbbeyEngine
    @State private var showResetConfirm = false
    @State private var showAbout = false
    @State private var showHelp = false

    init() {
        let bootstrap = AbbeyStore.bootstrap()
        let engine = AbbeyEngine(modelContainer: bootstrap.container)
        if bootstrap.degraded {
            engine.metrics.markStoreDegraded()
        }
        _engine = State(initialValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .frame(minWidth: 920, minHeight: 580)
                .navigationTitle("Abbey Companion · \(engine.config.operatingMode.rawValue)")
                .onReceive(NotificationCenter.default.publisher(for: .abbeyResetStoreRequested)) { _ in
                    showResetConfirm = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .abbeyAboutRequested)) { _ in
                    showAbout = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .abbeyHelpRequested)) { _ in
                    showHelp = true
                }
                .confirmationDialog(
                    "Reset local SwiftData store?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset Store", role: .destructive) {
                        try? engine.resetLocalStore()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Deletes messages, users, channels, reputation events, activity logs, and equity ideas. Settings knobs are kept.")
                }
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
                .alert("Abbey commands", isPresented: $showHelp) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("!help · !rep [user] · !persona [name] · !status · !consolidate · !kick|!ban|!purge <user> [reason]")
                }
        }
        .modelContainer(engine.modelContainer)
        .defaultSize(width: 1100, height: 720)
        .commands {
            AbbeyCommands(engine: engine)
        }

        Settings {
            SettingsView()
                .environment(engine)
                .modelContainer(engine.modelContainer)
        }
    }
}
