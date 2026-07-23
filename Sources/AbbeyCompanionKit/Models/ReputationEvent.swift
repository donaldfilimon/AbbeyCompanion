import Foundation
import SwiftData

/// Mirrors `ReputationEvent` — an audit trail row for every reputation delta SocialBrain
/// applies, so the Users view can show "why" a score moved, not just the current value.
@Model
package final class ReputationEvent {
    package var userId: String
    package var guildId: String
    package var delta: Double
    package var reason: String
    package var createdAt: Date

    /// Inverse of `UserMemory.reputationEvents`. `userId`/`guildId` stay denormalized for
    /// `#Predicate` filters that shouldn't hop the relationship.
    package var user: UserMemory?

    package init(
        userId: String,
        guildId: String,
        delta: Double,
        reason: String,
        createdAt: Date = .now,
        user: UserMemory? = nil
    ) {
        self.userId = userId
        self.guildId = guildId
        self.delta = delta
        self.reason = reason
        self.createdAt = createdAt
        self.user = user
    }
}
