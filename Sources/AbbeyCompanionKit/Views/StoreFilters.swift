import Foundation
import SwiftData

/// Pure filter helpers for SwiftUI `@Query` surfaces — unit-testable without rendering views.
package enum StoreFilters {
    package static func userMatchesSearch(_ user: UserMemory, needle: String) -> Bool {
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if user.discordUserId.localizedCaseInsensitiveContains(trimmed) { return true }
        if user.guildId.localizedCaseInsensitiveContains(trimmed) { return true }
        if user.facts.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
        return false
    }

    package static func filterUsers(_ users: [UserMemory], search: String) -> [UserMemory] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return users }
        return users.filter { userMatchesSearch($0, needle: trimmed) }
    }

    package static func messageMatchesChannel(_ message: GuildMessage, channelFilter: String) -> Bool {
        let trimmed = channelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return message.channelId == trimmed
    }

    package static func messageMatchesSearch(_ message: GuildMessage, needle: String) -> Bool {
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if message.authorId.localizedCaseInsensitiveContains(trimmed) { return true }
        if message.content.localizedCaseInsensitiveContains(trimmed) { return true }
        if message.channelId.localizedCaseInsensitiveContains(trimmed) { return true }
        if message.guildId.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }

    package static func filterMessages(
        _ messages: [GuildMessage],
        channelFilter: String,
        search: String
    ) -> [GuildMessage] {
        messages.filter { message in
            messageMatchesChannel(message, channelFilter: channelFilter)
                && messageMatchesSearch(message, needle: search)
        }
    }

    package static func sortedReputationEvents(for user: UserMemory) -> [ReputationEvent] {
        user.reputationEvents.sorted { $0.createdAt > $1.createdAt }
    }
}
