import Foundation
import SwiftData

/// Mirrors `GuildMessage` from the Vapor/Fluent bot (see bot-architecture.md).
/// This is a local persisted message log, not a live cache of Discord's message store.
@Model
package final class GuildMessage {
    @Attribute(.unique) var discordMessageId: String
    package var channelId: String
    package var guildId: String
    package var authorId: String
    package var content: String
    package var createdAt: Date

    package init(discordMessageId: String, channelId: String, guildId: String, authorId: String, content: String, createdAt: Date = .now) {
        self.discordMessageId = discordMessageId
        self.channelId = channelId
        self.guildId = guildId
        self.authorId = authorId
        self.content = content
        self.createdAt = createdAt
    }
}
