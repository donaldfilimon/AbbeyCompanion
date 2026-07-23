import Foundation
import SwiftData

/// Mirrors `UserMemory` from the Vapor/Fluent bot. Per-user, per-guild fact store plus
/// the SocialBrain reputation score (0.0–1.0).
@Model
package final class UserMemory {
    package var discordUserId: String
    package var guildId: String
    package var facts: [String]
    package var reputation: Double
    package var interactionCount: Int
    package var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ReputationEvent.user)
    package var reputationEvents: [ReputationEvent]

    package init(
        discordUserId: String,
        guildId: String,
        facts: [String] = [],
        reputation: Double = 0.5,
        interactionCount: Int = 0,
        updatedAt: Date = .now
    ) {
        self.discordUserId = discordUserId
        self.guildId = guildId
        self.facts = facts
        self.reputation = reputation
        self.interactionCount = interactionCount
        self.updatedAt = updatedAt
        self.reputationEvents = []
    }

    package var compositeKey: String { "\(guildId):\(discordUserId)" }
}
