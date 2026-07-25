import Foundation
import SwiftData
import Testing
import AbbeyCore
import AbbeyCompanionKit

@Suite("AbbeyCompanionKit Ingest", .serialized)
@MainActor
struct AbbeyIngestTests {
    private let channel = AbbeyKitTestSupport.channel
    private let guild = AbbeyKitTestSupport.guild
    private let author = AbbeyKitTestSupport.author

    @Test("greeting ingest sets intent and usually produces a reply")
    func greetingIngest() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
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
            let stored = try AbbeyKitTestSupport.messageCount(in: engine)
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
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            _ = await engine.ingestMessage(
                content: "remember I like Zig",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(engine.lastIntent == .memoryStore)
            let facts = try AbbeyKitTestSupport.userFacts(in: engine, userId: author, guildId: guild)
            #expect(facts.contains("I like Zig"))
        }
    }

    @Test("slash !help and !rep return deterministic replies")
    func slashCommands() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
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
        let source = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            _ = await source.ingestMessage(
                content: "remember export me",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            let data = try source.exportJSON()
            #expect(!data.isEmpty)

            let dest = try AbbeyKitTestSupport.makeEngine()
            let counts = try dest.importJSON(data)
            #expect(counts.messages >= 1)
            #expect(counts.users >= 1)
            let facts = try AbbeyKitTestSupport.userFacts(in: dest, userId: author, guildId: guild)
            #expect(facts.contains("export me"))
        }
    }

    @Test("reply cooldown arms and skips subsequent replies")
    func replyCooldown() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig(cooldownSeconds: 120) {
            await engine.scheduler.markReplied(userId: "cooldown-user", guildId: guild)
            let remaining = await engine.scheduler.cooldownRemaining(
                userId: "cooldown-user",
                guildId: guild
            )
            #expect(remaining > 100)

            var sawCooldownSkip = false
            for _ in 0..<60 {
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
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
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

    @Test("batch transcript replay ingests non-comment lines")
    func batchReplay() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            let transcript = """
            # setup
            hey abbey
            remember batch facts

            what is my reputation?
            """
            let count = await engine.ingestBatch(
                transcript: transcript,
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            #expect(count == 3)
            #expect(engine.lastBatchIngestCount == 3)
            let stored = try AbbeyKitTestSupport.messageCount(in: engine)
            #expect(stored >= 3)
        }
    }

    @Test("SwiftData relationships link messages and reputation events")
    func swiftDataRelationships() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            _ = await engine.ingestMessage(
                content: "hey there",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            let context = ModelContext(engine.modelContainer)
            let channels = try context.fetch(FetchDescriptor<ChannelContext>())
            #expect(channels.contains { $0.channelId == channel && !$0.messages.isEmpty })

            let users = try context.fetch(FetchDescriptor<UserMemory>())
            #expect(users.contains { user in
                user.discordUserId == author && user.guildId == guild && !user.reputationEvents.isEmpty
            })
        }
    }

    @Test("StoreFilters user search matches userId guildId and facts")
    func userSearchFilter() throws {
        let zigUser = UserMemory(discordUserId: "donald", guildId: "dev-guild", facts: ["ships Zig"])
        let other = UserMemory(discordUserId: "alice", guildId: "other-guild", facts: ["likes Swift"])
        let users = [zigUser, other]

        #expect(StoreFilters.filterUsers(users, search: "donald").count == 1)
        #expect(StoreFilters.filterUsers(users, search: "dev-guild").count == 1)
        #expect(StoreFilters.filterUsers(users, search: "zig").count == 1)
        #expect(StoreFilters.filterUsers(users, search: "").count == 2)
        #expect(StoreFilters.filterUsers(users, search: "nomatch").isEmpty)
    }

    @Test("StoreFilters channel filter returns exact channel rows")
    func channelFilterHelper() throws {
        let general = GuildMessage(
            discordMessageId: "m1",
            channelId: "general",
            guildId: guild,
            authorId: author,
            content: "hi"
        )
        let mods = GuildMessage(
            discordMessageId: "m2",
            channelId: "mods",
            guildId: guild,
            authorId: author,
            content: "mod talk"
        )
        let all = [general, mods]

        #expect(StoreFilters.filterMessages(all, channelFilter: "general", search: "").count == 1)
        #expect(StoreFilters.filterMessages(all, channelFilter: "general", search: "").first?.channelId == "general")
        #expect(StoreFilters.filterMessages(all, channelFilter: "", search: "").count == 2)
        #expect(StoreFilters.filterMessages(all, channelFilter: "missing", search: "").isEmpty)
    }

    @Test("reputation events grow on repeated ingest without recreating engine")
    func liveReputationEvents() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            _ = await engine.ingestMessage(
                content: "hello",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            let firstCount = try AbbeyKitTestSupport.reputationEventCount(
                in: engine, userId: author, guildId: guild
            )
            #expect(firstCount >= 1)

            _ = await engine.ingestMessage(
                content: "hello again",
                channelId: channel,
                guildId: guild,
                authorId: author
            )
            let secondCount = try AbbeyKitTestSupport.reputationEventCount(
                in: engine, userId: author, guildId: guild
            )
            #expect(secondCount > firstCount)

            let user = try AbbeyKitTestSupport.fetchUser(in: engine, userId: author, guildId: guild)
            #expect(StoreFilters.sortedReputationEvents(for: user).count == secondCount)
        }
    }

    @Test("reaction reward credits stored policy once")
    func reactionReward() async throws {
        let engine = try AbbeyKitTestSupport.makeEngine()
        try await AbbeyKitTestSupport.withTestConfig {
            for _ in 0..<25 {
                _ = await engine.ingestMessage(
                    content: "hello there friend",
                    channelId: channel,
                    guildId: guild,
                    authorId: author
                )
                if let message = try AbbeyKitTestSupport.firstPolicyMessage(in: engine) {
                    let ok = await engine.applyReaction(to: message, reward: 1)
                    #expect(ok)
                    let again = await engine.applyReaction(to: message, reward: 1)
                    #expect(!again)
                    return
                }
            }
            Issue.record("expected a message with an attached DQN policy")
        }
    }
}
