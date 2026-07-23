import Foundation

/// Persistence façade. Backed by SwiftData (see `SwiftDataStack`); the public
/// `save`/`load` surface is unchanged so callers (e.g. `ConversationStore`) are
/// unaffected by the migration away from the JSON file.
@MainActor
enum ConversationPersistence {
    static func save(_ conversations: [Conversation]) {
        SwiftDataStack.shared.save(conversations)
    }

    static func load() -> [Conversation] {
        SwiftDataStack.shared.load()
    }

    /// Human-readable description of the last persistence failure, or `nil` if
    /// the on-disk store is healthy. GUI uses this to show a non-blocking banner.
    static var lastError: String? {
        SwiftDataStack.shared.lastError
    }
}
