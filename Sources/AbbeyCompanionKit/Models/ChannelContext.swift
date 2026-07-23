import Foundation
import SwiftData

/// Mirrors `ChannelContext` from the Vapor/Fluent bot — a rolling, compressed summary
/// of recent channel activity, recomputed on the cadence set by
/// `AppConfig.memoryConsolidationIntervalMinutes` (ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN).
@Model
package final class ChannelContext {
    @Attribute(.unique) var channelId: String
    package var guildId: String
    package var summary: String
    package var messageCount: Int
    package var updatedAt: Date

    package init(channelId: String, guildId: String, summary: String = "", messageCount: Int = 0, updatedAt: Date = .now) {
        self.channelId = channelId
        self.guildId = guildId
        self.summary = summary
        self.messageCount = messageCount
        self.updatedAt = updatedAt
    }
}
