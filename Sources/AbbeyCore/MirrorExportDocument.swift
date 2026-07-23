import Foundation

/// Portable mirror handoff document — same payload AbbeyCompanion export/import uses.
/// Lives in AbbeyCore so round-trips are unit-testable without the SwiftUI target.
public struct MirrorExportDocument: Codable, Sendable, Equatable {
    public struct Message: Codable, Sendable, Equatable {
        public var discordMessageId: String
        public var channelId: String
        public var guildId: String
        public var authorId: String
        public var content: String
        public var createdAt: Date

        public init(
            discordMessageId: String,
            channelId: String,
            guildId: String,
            authorId: String,
            content: String,
            createdAt: Date
        ) {
            self.discordMessageId = discordMessageId
            self.channelId = channelId
            self.guildId = guildId
            self.authorId = authorId
            self.content = content
            self.createdAt = createdAt
        }
    }

    public struct User: Codable, Sendable, Equatable {
        public var discordUserId: String
        public var guildId: String
        public var facts: [String]
        public var reputation: Double
        public var interactionCount: Int

        public init(
            discordUserId: String,
            guildId: String,
            facts: [String],
            reputation: Double,
            interactionCount: Int
        ) {
            self.discordUserId = discordUserId
            self.guildId = guildId
            self.facts = facts
            self.reputation = reputation
            self.interactionCount = interactionCount
        }
    }

    public struct Channel: Codable, Sendable, Equatable {
        public var channelId: String
        public var guildId: String
        public var summary: String
        public var messageCount: Int

        public init(channelId: String, guildId: String, summary: String, messageCount: Int) {
            self.channelId = channelId
            self.guildId = guildId
            self.summary = summary
            self.messageCount = messageCount
        }
    }

    public var exportedAt: Date
    public var messages: [Message]
    public var users: [User]
    public var channels: [Channel]

    public init(exportedAt: Date = .now, messages: [Message], users: [User], channels: [Channel]) {
        self.exportedAt = exportedAt
        self.messages = messages
        self.users = users
        self.channels = channels
    }

    public static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func encode() throws -> Data {
        try Self.jsonEncoder.encode(self)
    }

    public static func decode(from data: Data) throws -> MirrorExportDocument {
        try jsonDecoder.decode(MirrorExportDocument.self, from: data)
    }
}
