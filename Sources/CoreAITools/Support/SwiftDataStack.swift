import Foundation
import SwiftData

/// SwiftData-backed persistence for conversations.
///
/// The on-disk store replaces the previous JSON-file approach with a real
/// Core Data / SwiftData SQLite store: crash-safe writes, indexed queries,
/// and automatic change tracking. The public API mirrors the old
/// `ConversationPersistence` surface so the rest of the app is untouched.
@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    private let container: ModelContainer
    private let context: ModelContext

    /// Set when the on-disk store is unavailable (corrupt/locked). The GUI can
    /// surface this so the user knows history is session-only.
    private(set) var lastError: String?

    private init() {
        let schema = Schema([PersistedConversation.self])
        let url = Self.storeURL()
        let config = ModelConfiguration(
            schema: schema,
            url: url,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Quarantine the corrupt store so we don't fall back to in-memory
            // on every subsequent launch (which would silently lose history each time).
            Self.quarantineIfExists(url)
            do {
                let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [memConfig])
            } catch {
                fatalError("SwiftData: unable to create even an in-memory store: \(error)")
            }
            lastError = "Conversation history is session-only (store was corrupt and quarantined): \(error.localizedDescription)"
            print("SwiftData: fell back to in-memory store (\(error.localizedDescription))")
        }
        context = container.mainContext
        context.autosaveEnabled = false
    }

    /// Moves a corrupt store file aside (appending a timestamp) so a fresh
    /// store is created on the next launch instead of re-failing forever.
    private static func quarantineIfExists(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let stamped = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))")
        try? fm.moveItem(at: url, to: stamped)
    }

    private static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = appSupport.appendingPathComponent("CoreAIAssistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.store")
    }

    // MARK: - Save

    func save(_ conversations: [Conversation]) {
        do {
            try context.delete(model: PersistedConversation.self)
            // Insert each conversation independently so one un-encodable
            // conversation can't discard the entire unsaved batch.
            for convo in conversations {
                do {
                    let entity = try PersistedConversation(from: convo)
                    context.insert(entity)
                } catch {
                    print("SwiftData: skipped saving conversation \(convo.id) (\(error.localizedDescription))")
                }
            }
            try context.save()
            lastError = nil
        } catch {
            lastError = "Could not save conversation history: \(error.localizedDescription)"
            print("SwiftData: failed to save conversations: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    func load() -> [Conversation] {
        let descriptor = FetchDescriptor<PersistedConversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let entities = try? context.fetch(descriptor) else { return [] }
        let conversations = entities.compactMap { $0.toConversation() }
        if conversations.isEmpty {
            // First run: import any legacy JSON so existing history is preserved.
            return Self.importLegacyJSON()
        }
        return conversations
    }

    // MARK: - Legacy import

    private static func importLegacyJSON() -> [Conversation] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let legacy = appSupport.appendingPathComponent("CoreAIAssistant/conversations.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return [] }
        do {
            let data = try Data(contentsOf: legacy)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([Conversation].self, from: data)
            return decoded
        } catch {
            return []
        }
    }
}

@Model
final class PersistedConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var projectPath: String?
    var createdAt: Date
    var updatedAt: Date
    var modelChoiceRaw: String
    var workModeRaw: String
    var messagesData: Data
    var fileChangesData: Data

    init(from convo: Conversation) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.id = convo.id
        self.title = convo.title
        self.projectPath = convo.projectPath
        self.createdAt = convo.createdAt
        self.updatedAt = convo.updatedAt
        self.modelChoiceRaw = convo.modelChoice.rawValue
        self.workModeRaw = convo.workMode.rawValue
        self.messagesData = try encoder.encode(convo.messages)
        self.fileChangesData = try encoder.encode(convo.fileChanges)
    }

    func toConversation() -> Conversation? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let messages = try? decoder.decode([ChatMessage].self, from: messagesData),
              let fileChanges = try? decoder.decode([FileChange].self, from: fileChangesData) else { return nil }
        let modelChoice = Conversation.ModelChoice(rawValue: modelChoiceRaw) ?? .systemDefault
        let workMode = WorkMode(rawValue: workModeRaw) ?? .execute
        return Conversation(
            id: id,
            title: title,
            messages: messages,
            projectPath: projectPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fileChanges: fileChanges,
            modelChoice: modelChoice,
            workMode: workMode
        )
    }
}
