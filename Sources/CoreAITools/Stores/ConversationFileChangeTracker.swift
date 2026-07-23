import Foundation

/// Pure helpers for mapping model tool calls onto conversation file-change records.
enum ConversationFileChangeTracker {
    static func apply(toolCalls: [ToolCallRecord], to convo: inout Conversation) {
        for call in toolCalls {
            switch call.name {
            case "write_file":
                if let path = extractPath(from: call.argumentsSummary) {
                    let exists = FileManager.default.fileExists(atPath: path)
                    let change = FileChange(path: path, changeType: exists ? .modified : .created)
                    if !convo.fileChanges.contains(where: { $0.path == path }) {
                        convo.fileChanges.append(change)
                    }
                }
            case "apply_edit":
                if let path = extractPath(from: call.argumentsSummary) {
                    let change = FileChange(path: path, changeType: .modified)
                    if !convo.fileChanges.contains(where: { $0.path == path }) {
                        convo.fileChanges.append(change)
                    }
                }
            case "git_restore":
                let target = call.argumentsSummary.contains("all files")
                    ? "(all)"
                    : extractPath(from: call.argumentsSummary) ?? "(unknown)"
                let change = FileChange(path: target, changeType: .deleted)
                if !convo.fileChanges.contains(where: { $0.path == target }) {
                    convo.fileChanges.append(change)
                }
            default:
                break
            }
        }
    }

    static func extractPath(from summary: String) -> String? {
        guard let range = summary.range(of: "path:") else { return nil }
        let after = summary[range.upperBound...]
        let trimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if let endIdx = trimmed.firstIndex(where: { $0 == "\n" || $0 == "," }) {
            return String(trimmed[..<endIdx]).trimmingCharacters(in: .whitespaces)
        }
        return String(trimmed)
    }
}
