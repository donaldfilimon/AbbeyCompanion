import Foundation

public struct IntentClassifier {
    public enum Intent: String, CaseIterable, Sendable {
        case question, greeting, modRequest, memoryStore, personaSwitch,
             repQuery, smallTalk, command, unknown

        public var quality: Double {
            switch self {
            case .question, .modRequest, .memoryStore: return 0.8
            case .greeting, .smallTalk: return 0.5
            case .unknown: return 0.2
            default: return 0.6
            }
        }
    }

    /// OPEN DECISION (flagged, not silently resolved — see /areas/discord-abbey-skill.md):
    /// `.unknown` is unreachable in `classify` as written, because `.smallTalk` is
    /// the unconditional fallback. Use `classifyStrict` when tiny/non-letter input
    /// should become `.unknown` instead.
    public static func classify(_ text: String) -> Intent {
        let lower = text.lowercased()
        if lower.hasPrefix("!") || lower.hasPrefix("/") {
            if isModCommand(lower) { return .modRequest }
            return .command
        }
        if lower.contains("kick") || lower.contains("ban") || lower.contains("purge")
            || lower.contains("timeout") || lower.contains("mod ") || lower.hasPrefix("mod ") {
            return .modRequest
        }
        if lower.contains("remember") || lower.contains("note that") { return .memoryStore }
        if lower.contains("reputation") || lower.contains(" my rep") || lower.hasPrefix("rep ") {
            return .repQuery
        }
        if lower.contains("switch") || lower.contains("be aviva") || lower.contains("be abi")
            || lower.contains("be abbey") {
            return .personaSwitch
        }
        if lower.hasSuffix("?") || lower.hasPrefix("what") || lower.hasPrefix("how")
            || lower.hasPrefix("why") || lower.hasPrefix("who") {
            return .question
        }
        if ["hi", "hey", "yo", "sup", "hello"].contains(where: { lower.hasPrefix($0) }) {
            return .greeting
        }
        return .smallTalk
    }

    public static func classifyStrict(_ text: String) -> Intent {
        let result = classify(text)
        guard result == .smallTalk else { return result }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLetters = trimmed.contains { $0.isLetter }
        guard trimmed.count >= 2, hasLetters else { return .unknown }
        return .smallTalk
    }

    public static func suggestCompletions(for partial: String) -> [String] {
        let corpus = [
            "what do you think about",
            "how does",
            "can you help me with",
            "remember ",
            "note that ",
            "what is my reputation",
            "switch to aviva",
            "switch to abi",
            "switch to abbey",
            "!kick ",
            "!ban ",
            "!purge ",
            "!help",
            "!rep ",
            "!persona ",
            "!status",
            "!consolidate"
        ]
        let needle = partial.lowercased()
        guard !needle.isEmpty else { return Array(corpus.prefix(6)) }
        return corpus.filter { $0.hasPrefix(needle) }
    }

    /// Parses `!kick user reason`, `/ban user`, `!purge user …`.
    public static func parseModCommand(_ text: String) -> (kind: String, target: String, reason: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!") || trimmed.hasPrefix("/") else { return nil }
        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let verb = parts.first?.lowercased() else { return nil }
        let kind: String
        switch verb {
        case "kick", "timeout": kind = "kick"
        case "ban": kind = "ban"
        case "purge": kind = "purge"
        default: return nil
        }
        parts.removeFirst()
        guard let target = parts.first, !target.isEmpty else { return nil }
        parts.removeFirst()
        let reason = parts.isEmpty ? "unspecified" : parts.joined(separator: " ")
        return (kind, target, reason)
    }

    private static func isModCommand(_ lower: String) -> Bool {
        let body = lower.drop(while: { $0 == "!" || $0 == "/" })
        return body.hasPrefix("kick") || body.hasPrefix("ban") || body.hasPrefix("purge")
            || body.hasPrefix("timeout")
    }
}
