import Foundation
import SwiftData

/// Mirrors `GuildMessage` from the Vapor/Fluent bot (see bot-architecture.md).
/// This is a local persisted message log, not a live cache of Discord's message store.
@Model
package final class GuildMessage {
    @Attribute(.unique) package var discordMessageId: String
    package var channelId: String
    package var guildId: String
    package var authorId: String
    package var content: String
    package var createdAt: Date
    /// Companion reaction tally (👍 positive / 👎 negative) for training feedback.
    package var reactionCount: Int
    /// 8-dim DQN state captured when Abbey chose a policy action for this turn.
    package var policyState: [Double]
    /// DQN action index (`-1` = none recorded).
    package var policyAction: Int
    /// True once a UI reaction has already credited this policy decision.
    package var hasPolicyReward: Bool

    /// Optional link to the channel row for relationship-aware deletes / navigation.
    package var channel: ChannelContext?

    package init(
        discordMessageId: String,
        channelId: String,
        guildId: String,
        authorId: String,
        content: String,
        createdAt: Date = .now,
        reactionCount: Int = 0,
        policyState: [Double] = [],
        policyAction: Int = -1,
        hasPolicyReward: Bool = false,
        channel: ChannelContext? = nil
    ) {
        self.discordMessageId = discordMessageId
        self.channelId = channelId
        self.guildId = guildId
        self.authorId = authorId
        self.content = content
        self.createdAt = createdAt
        self.reactionCount = reactionCount
        self.policyState = policyState
        self.policyAction = policyAction
        self.hasPolicyReward = hasPolicyReward
        self.channel = channel
    }

    package var hasPolicy: Bool {
        policyAction >= 0 && policyState.count == 8
    }
}
