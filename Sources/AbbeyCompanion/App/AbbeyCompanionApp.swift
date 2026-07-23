import SwiftUI
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
        let bootstrap = Self.makeModelContainer()
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
        }
    }

    private struct Bootstrap {
        let container: ModelContainer
        let degraded: Bool
    }

    private static func makeModelContainer() -> Bootstrap {
        let schema = Schema([
            GuildMessage.self,
            UserMemory.self,
            ChannelContext.self,
            ReputationEvent.self,
            InteractionLog.self,
            EquityIdea.self
        ])
        let configuration = ModelConfiguration(
            "AbbeyCompanionStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return Bootstrap(
                container: try ModelContainer(for: schema, configurations: [configuration]),
                degraded: false
            )
        } catch {
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return Bootstrap(
                    container: try ModelContainer(for: schema, configurations: [fallback]),
                    degraded: true
                )
            } catch {
                fatalErrorUnrecoverable(error)
            }
        }
    }

    private static func fatalErrorUnrecoverable(_ error: Error) -> Never {
        fatalError("AbbeyCompanion: could not construct any ModelContainer, in-memory fallback included: \(error)")
    }
}
