import Foundation
import SwiftData

/// Mirrors `ReputationEvent` — an audit trail row for every reputation delta SocialBrain
/// applies, so the Users view can show "why" a score moved, not just the current value.
@Model
final class ReputationEvent {
    var userId: String
    var guildId: String
    var delta: Double
    var reason: String
    var createdAt: Date

    init(userId: String, guildId: String, delta: Double, reason: String, createdAt: Date = .now) {
        self.userId = userId
        self.guildId = guildId
        self.delta = delta
        self.reason = reason
        self.createdAt = createdAt
    }
}
