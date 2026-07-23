import Foundation
import SwiftData

/// Mirrors `GuildMessage` from the Vapor/Fluent bot (see bot-architecture.md).
/// This is a local persisted message log, not a live cache of Discord's message store.
@Model
final class GuildMessage {
    @Attribute(.unique) var discordMessageId: String
    var channelId: String
    var guildId: String
    var authorId: String
    var content: String
    var createdAt: Date

    init(discordMessageId: String, channelId: String, guildId: String, authorId: String, content: String, createdAt: Date = .now) {
        self.discordMessageId = discordMessageId
        self.channelId = channelId
        self.guildId = guildId
        self.authorId = authorId
        self.content = content
        self.createdAt = createdAt
    }
}
