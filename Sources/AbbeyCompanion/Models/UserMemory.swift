import Foundation
import SwiftData

/// Mirrors `UserMemory` from the Vapor/Fluent bot. Per-user, per-guild fact store plus
/// the SocialBrain reputation score (0.0–1.0).
@Model
final class UserMemory {
    var discordUserId: String
    var guildId: String
    var facts: [String]
    var reputation: Double
    var interactionCount: Int
    var updatedAt: Date

    init(discordUserId: String, guildId: String, facts: [String] = [], reputation: Double = 0.5, interactionCount: Int = 0, updatedAt: Date = .now) {
        self.discordUserId = discordUserId
        self.guildId = guildId
        self.facts = facts
        self.reputation = reputation
        self.interactionCount = interactionCount
        self.updatedAt = updatedAt
    }

    var compositeKey: String { "\(guildId):\(discordUserId)" }
}
