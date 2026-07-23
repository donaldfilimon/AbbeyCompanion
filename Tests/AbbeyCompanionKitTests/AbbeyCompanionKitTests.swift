import Foundation
import SwiftData
import Testing
import AbbeyCore
import AbbeyCompanionKit

@Suite("AbbeyCompanionKit", .serialized)
@MainActor
struct AbbeyCompanionKitTests {
    private let channel = "ch-test"
    private let guild = "guild-test"
    private let author = "user-test"

    @Test("greeting ingest sets intent and usually produces a reply")
    func greetingIngest() async throws {
        let engine = try makeEngine()
        try await withTestConfig {
            var reply: PersonaResponse?
            for _ in 0..<20 {
                reply = await engine.ingestMessage(
                    content: "hey Abbey",
                    channelId: channel,
                    guildId: guild,
                    authorId: author
                )
                if reply != nil { break }
                if engine.lastReplySkippedReason?.contains("cooldown") == true { break }
            }
            #expect(engine.lastIntent == .greeting)
            let stored = try messageCount(in: engine)
            #expect(stored >= 1)
            if let reply {
                #expect(!reply.text.isEmpty)
            } else {
                #expect(engine.lastDQNAction == .ignore || engine.lastReplySkippedReason != nil)
            }
        }
    }

    @Test("remember stores a user fact even when DQN ignores")
    func memoryStoresFact() async throws {
        let engine = try makeEngine()
        try await withTestConfig {
            _ = await engine.ingestMessage(
                content: "remember I like Zig",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(engine.lastIntent == .memoryStore)
            let facts = try userFacts(in: engine, userId: author, guildId: guild)
            #expect(facts.contains("I like Zig"))
        }
    }

    @Test("slash !help and !rep return deterministic replies")
    func slashCommands() async throws {
        let engine = try makeEngine()
        try await withTestConfig {
            let help = await engine.ingestMessage(
                content: "!help",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(engine.lastIntent == .command)
            #expect(help?.text.contains("!help") == true)

            let rep = await engine.ingestMessage(
                content: "!rep",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(rep?.text.contains("Reputation for \(author)") == true)
        }
    }

    @Test("exportJSON / importJSON round-trips messages and facts")
    func exportImportRoundTrip() async throws {
        let source = try makeEngine()
        try await withTestConfig {
            _ = await source.ingestMessage(
                content: "remember export me",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            let data = try source.exportJSON()
            #expect(!data.isEmpty)

            let dest = try makeEngine()
            let counts = try dest.importJSON(data)
            #expect(counts.messages >= 1)
            #expect(counts.users >= 1)
            let facts = try userFacts(in: dest, userId: author, guildId: guild)
            #expect(facts.contains("export me"))
        }
    }

    @Test("reply cooldown arms after a successful reply")
    func replyCooldown() async throws {
        let engine = try makeEngine()
        try await withTestConfig(cooldownSeconds: 120) {
            var gotReply = false
            for _ in 0..<30 {
                if await engine.ingestMessage(
                    content: "hello friend",
                    channelId: channel,
                    guildId: guild,
                    authorId: "cooldown-user"
                ) != nil {
                    gotReply = true
                    break
                }
            }
            #expect(gotReply)
            let remaining = await engine.scheduler.cooldownRemaining(
                userId: "cooldown-user",
                guildId: guild
            )
            #expect(remaining > 0)

            // DQN ignore is checked before cooldown; retry until a non-ignore turn.
            var sawCooldownSkip = false
            for _ in 0..<40 {
                let second = await engine.ingestMessage(
                    content: "hello again",
                    channelId: channel,
                    guildId: guild,
                    authorId: "cooldown-user"
                )
                if engine.lastReplySkippedReason?.contains("cooldown") == true {
                    #expect(second == nil)
                    sawCooldownSkip = true
                    break
                }
                #expect(second == nil, "cooldown window should not produce a reply")
            }
            #expect(sawCooldownSkip)
        }
    }

    @Test("DQN selects an action on non-slash ingest")
    func dqnSelectsAction() async throws {
        let engine = try makeEngine()
        try await withTestConfig {
            _ = await engine.ingestMessage(
                content: "what is Abbey?",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(engine.lastIntent == .question)
            #expect(engine.lastDQNAction != nil)
        }
    }

    // MARK: - Helpers

    private func makeEngine() throws -> AbbeyEngine {
        let schema = Schema([
            GuildMessage.self,
            UserMemory.self,
            ChannelContext.self,
            ReputationEvent.self,
            InteractionLog.self,
            EquityIdea.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return AbbeyEngine(modelContainer: container)
    }

    private func withTestConfig(
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

    private func messageCount(in engine: AbbeyEngine) throws -> Int {
        let context = ModelContext(engine.modelContainer)
        return try context.fetchCount(FetchDescriptor<GuildMessage>())
    }

    private func userFacts(in engine: AbbeyEngine, userId: String, guildId: String) throws -> [String] {
        let context = ModelContext(engine.modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        return try context.fetch(descriptor).first?.facts ?? []
    }
}
