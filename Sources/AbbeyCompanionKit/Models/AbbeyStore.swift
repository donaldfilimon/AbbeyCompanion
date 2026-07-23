import Foundation
import SwiftData

/// Single source of truth for the companion SwiftData schema and container factories.
/// App launch, previews, and tests all go through here so model lists cannot drift.
package enum AbbeyStore {
    package static let schema = Schema([
        GuildMessage.self,
        UserMemory.self,
        ChannelContext.self,
        ReputationEvent.self,
        InteractionLog.self,
        EquityIdea.self
    ])

    package static let storeName = "AbbeyCompanionStore"

    /// Persistent on-disk store (Application Support via SwiftData defaults).
    package static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Ephemeral container for tests and SwiftUI previews.
    package static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Launch helper: disk first, then in-memory fallback (marks degraded for UI).
    package static func bootstrap() -> (container: ModelContainer, degraded: Bool) {
        do {
            return (try makeContainer(), false)
        } catch {
            do {
                return (try makeInMemoryContainer(), true)
            } catch {
                fatalError("AbbeyCompanion: could not construct any ModelContainer: \(error)")
            }
        }
    }

    @MainActor
    package static func makePreviewEngine(seedDemo: Bool = false) -> AbbeyEngine {
        let container = (try? makeInMemoryContainer())
            ?? {
                fatalError("AbbeyCompanion preview container failed")
            }()
        let engine = AbbeyEngine(
            modelContainer: container,
            dqnCheckpointURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("abbey-preview-dqn-\(UUID().uuidString).json")
        )
        if seedDemo {
            Task { await engine.seedDemoData() }
        }
        return engine
    }
}
