import Foundation
import SwiftData
import AbbeyCore

/// Canonical SwiftData access for AbbeyCompanionKit. Keeps ModelContext usage out of the orchestrator.
@MainActor
package final class AbbeyPersistence {
    package let modelContainer: ModelContainer

    package init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Messages / channels

    @discardableResult
    package func insertInboundMessage(
        messageId: String,
        content: String,
        channelId: String,
        guildId: String,
        authorId: String
    ) throws -> GuildMessage {
        let context = ModelContext(modelContainer)
        let channel = upsertChannelContext(in: context, channelId: channelId, guildId: guildId)
        let message = GuildMessage(
            discordMessageId: messageId,
            channelId: channelId,
            guildId: guildId,
            authorId: authorId,
            content: content,
            channel: channel
        )
        context.insert(message)
        try context.save()
        return message
    }

    package func persistReply(_ response: PersonaResponse, channelId: String, guildId: String) {
        do {
            let context = ModelContext(modelContainer)
            let channel = upsertChannelContext(in: context, channelId: channelId, guildId: guildId, incrementCount: false)
            context.insert(
                GuildMessage(
                    discordMessageId: UUID().uuidString,
                    channelId: channelId,
                    guildId: guildId,
                    authorId: "abbey:\(response.personaName.lowercased())",
                    content: response.text,
                    channel: channel
                )
            )
            try context.save()
        } catch {
            // Reply still surfaces via lastReply on the engine.
        }
    }

    package func attachPolicy(to messageId: String, state: [Float], action: Int) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == messageId })
        guard let row = try? context.fetch(descriptor).first else { return }
        row.policyState = state.map { Double($0) }
        row.policyAction = action
        try? context.save()
    }

    package func applyReactionReward(to messageId: String, reward: Float) -> (state: [Float], action: Int)? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == messageId })
        guard let row = try? context.fetch(descriptor).first,
              row.hasPolicy,
              !row.hasPolicyReward
        else {
            return nil
        }
        let state = row.policyState.map { Float($0) }
        let action = row.policyAction
        row.reactionCount += reward >= 0 ? 1 : -1
        row.hasPolicyReward = true
        try? context.save()
        return (state, action)
    }

    package func deleteMessage(_ message: GuildMessage) {
        let context = ModelContext(modelContainer)
        let id = message.discordMessageId
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == id })
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
            try? context.save()
        }
    }

    package func clearChannel(channelId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.channelId == channelId })
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
            try? context.save()
        }
    }

    package func deleteChannelContext(channelId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(predicate: #Predicate { $0.channelId == channelId })
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
            try? context.save()
        }
    }

    package func clearActivityLogs() {
        let context = ModelContext(modelContainer)
        try? context.delete(model: InteractionLog.self)
        try? context.save()
    }

    package func resetLocalStore() throws {
        let context = ModelContext(modelContainer)
        try context.delete(model: GuildMessage.self)
        try context.delete(model: UserMemory.self)
        try context.delete(model: ChannelContext.self)
        try context.delete(model: ReputationEvent.self)
        try context.delete(model: InteractionLog.self)
        try context.delete(model: EquityIdea.self)
        try context.save()
    }

    package func removeFact(userId: String, guildId: String, fact: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        guard let user = try? context.fetch(descriptor).first else { return }
        user.facts.removeAll { $0 == fact }
        user.updatedAt = .now
        try? context.save()
    }

    package func logInteraction(command: String, userId: String, guildId: String, succeeded: Bool, started: ContinuousClock.Instant) {
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        let context = ModelContext(modelContainer)
        context.insert(
            InteractionLog(
                commandName: command,
                userId: userId,
                guildId: guildId,
                succeeded: succeeded,
                latencyMs: ms
            )
        )
        try? context.save()
    }

    // MARK: - Reads

    package func fetchChannelSummary(channelId: String) -> String {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        return (try? context.fetch(descriptor).first?.summary) ?? ""
    }

    package func fetchChannelMessageCount(channelId: String) -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        return (try? context.fetch(descriptor).first?.messageCount) ?? 0
    }

    package func fetchUserFacts(userId: String, guildId: String) -> [String] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        return (try? context.fetch(descriptor).first?.facts) ?? []
    }

    package func fetchUserInteractionCount(userId: String, guildId: String) -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        return (try? context.fetch(descriptor).first?.interactionCount) ?? 0
    }

    // MARK: - Mirror export / import

    package func mirrorSnapshot() throws -> [String: Int] {
        let context = ModelContext(modelContainer)
        return [
            "guildMessages": try context.fetchCount(FetchDescriptor<GuildMessage>()),
            "userMemories": try context.fetchCount(FetchDescriptor<UserMemory>()),
            "channelContexts": try context.fetchCount(FetchDescriptor<ChannelContext>()),
            "reputationEvents": try context.fetchCount(FetchDescriptor<ReputationEvent>()),
            "interactionLogs": try context.fetchCount(FetchDescriptor<InteractionLog>()),
            "equityIdeas": try context.fetchCount(FetchDescriptor<EquityIdea>())
        ]
    }

    package func exportJSON() throws -> Data {
        let context = ModelContext(modelContainer)
        let messages = try context.fetch(FetchDescriptor<GuildMessage>(sortBy: [SortDescriptor(\.createdAt)]))
        let users = try context.fetch(FetchDescriptor<UserMemory>())
        let channels = try context.fetch(FetchDescriptor<ChannelContext>())

        let doc = MirrorExportDocument(
            messages: messages.map {
                .init(
                    discordMessageId: $0.discordMessageId,
                    channelId: $0.channelId,
                    guildId: $0.guildId,
                    authorId: $0.authorId,
                    content: $0.content,
                    createdAt: $0.createdAt
                )
            },
            users: users.map {
                .init(
                    discordUserId: $0.discordUserId,
                    guildId: $0.guildId,
                    facts: $0.facts,
                    reputation: $0.reputation,
                    interactionCount: $0.interactionCount
                )
            },
            channels: channels.map {
                .init(
                    channelId: $0.channelId,
                    guildId: $0.guildId,
                    summary: $0.summary,
                    messageCount: $0.messageCount
                )
            }
        )
        return try doc.encode()
    }

    package func importJSON(_ data: Data) throws -> (messages: Int, users: Int, channels: Int) {
        let doc = try MirrorExportDocument.decode(from: data)
        let context = ModelContext(modelContainer)
        var mCount = 0, uCount = 0, cCount = 0

        for msg in doc.messages {
            let id = msg.discordMessageId
            let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == id })
            if (try? context.fetch(descriptor).first) != nil { continue }
            let channel = upsertChannelContext(
                in: context,
                channelId: msg.channelId,
                guildId: msg.guildId,
                incrementCount: false
            )
            context.insert(
                GuildMessage(
                    discordMessageId: msg.discordMessageId,
                    channelId: msg.channelId,
                    guildId: msg.guildId,
                    authorId: msg.authorId,
                    content: msg.content,
                    createdAt: msg.createdAt,
                    channel: channel
                )
            )
            mCount += 1
        }
        for user in doc.users {
            let uid = user.discordUserId
            let gid = user.guildId
            let descriptor = FetchDescriptor<UserMemory>(
                predicate: #Predicate { $0.discordUserId == uid && $0.guildId == gid }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.facts = Array(Set(existing.facts + user.facts))
                existing.reputation = user.reputation
                existing.interactionCount = max(existing.interactionCount, user.interactionCount)
                existing.updatedAt = .now
            } else {
                context.insert(
                    UserMemory(
                        discordUserId: user.discordUserId,
                        guildId: user.guildId,
                        facts: user.facts,
                        reputation: user.reputation,
                        interactionCount: user.interactionCount
                    )
                )
                uCount += 1
            }
        }
        for channel in doc.channels {
            let cid = channel.channelId
            let descriptor = FetchDescriptor<ChannelContext>(predicate: #Predicate { $0.channelId == cid })
            if let existing = try? context.fetch(descriptor).first {
                if channel.summary.count > existing.summary.count { existing.summary = channel.summary }
                existing.messageCount = max(existing.messageCount, channel.messageCount)
                existing.updatedAt = .now
            } else {
                context.insert(
                    ChannelContext(
                        channelId: channel.channelId,
                        guildId: channel.guildId,
                        summary: channel.summary,
                        messageCount: channel.messageCount
                    )
                )
                cCount += 1
            }
        }
        try context.save()
        return (mCount, uCount, cCount)
    }

    // MARK: - Internals

    @discardableResult
    package func upsertChannelContext(
        in context: ModelContext,
        channelId: String,
        guildId: String,
        incrementCount: Bool = true
    ) -> ChannelContext {
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        if let existing = try? context.fetch(descriptor).first {
            if incrementCount { existing.messageCount += 1 }
            existing.guildId = guildId
            existing.updatedAt = .now
            return existing
        }
        let created = ChannelContext(
            channelId: channelId,
            guildId: guildId,
            messageCount: incrementCount ? 1 : 0
        )
        context.insert(created)
        return created
    }
}
