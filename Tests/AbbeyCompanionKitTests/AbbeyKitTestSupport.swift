import Foundation
import SwiftData
import AbbeyCompanionKit

@MainActor
enum AbbeyKitTestSupport {
    static let channel = "ch-test"
    static let guild = "guild-test"
    static let author = "user-test"

    static func makeEngine() throws -> AbbeyEngine {
        let container = try AbbeyStore.makeInMemoryContainer()
        let checkpoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("abbey-kit-tests-\(UUID().uuidString).json")
        return AbbeyEngine(modelContainer: container, dqnCheckpointURL: checkpoint)
    }

    static func withTestConfig(
        cooldownSeconds: Double = 0,
        _ body: () async throws -> Void
    ) async throws {
        let config = AppConfig.shared
        let savedCooldown = config.replyCooldownSeconds
        let savedInference = config.inferenceMode
        let savedConfirm = config.confirmationRequiredForDestructiveActions
        let savedStrict = config.useStrictIntentClassification
        config.replyCooldownSeconds = cooldownSeconds
        config.inferenceMode = .deterministicFloor
        config.confirmationRequiredForDestructiveActions = false
        config.useStrictIntentClassification = false
        defer {
            config.replyCooldownSeconds = savedCooldown
            config.inferenceMode = savedInference
            config.confirmationRequiredForDestructiveActions = savedConfirm
            config.useStrictIntentClassification = savedStrict
        }
        try await body()
    }

    static func messageCount(in engine: AbbeyEngine) throws -> Int {
        let context = ModelContext(engine.modelContainer)
        return try context.fetchCount(FetchDescriptor<GuildMessage>())
    }

    static func userFacts(in engine: AbbeyEngine, userId: String, guildId: String) throws -> [String] {
        let context = ModelContext(engine.modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        return try context.fetch(descriptor).first?.facts ?? []
    }

    static func fetchUser(in engine: AbbeyEngine, userId: String, guildId: String) throws -> UserMemory {
        let context = ModelContext(engine.modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        guard let user = try context.fetch(descriptor).first else {
            throw NSError(
                domain: "AbbeyCompanionKitTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "user not found"]
            )
        }
        return user
    }

    static func reputationEventCount(in engine: AbbeyEngine, userId: String, guildId: String) throws -> Int {
        try StoreFilters.sortedReputationEvents(for: fetchUser(in: engine, userId: userId, guildId: guildId)).count
    }

    static func firstPolicyMessage(in engine: AbbeyEngine) throws -> GuildMessage? {
        let context = ModelContext(engine.modelContainer)
        let rows = try context.fetch(
            FetchDescriptor<GuildMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
        return rows.first(where: \.hasPolicy)
    }
}
