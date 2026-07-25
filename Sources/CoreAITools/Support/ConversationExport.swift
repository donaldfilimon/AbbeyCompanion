import Foundation
import AppKit
import UniformTypeIdentifiers

enum ConversationExport {
    static func exportAsMarkdown(_ conversation: Conversation) -> String {
        var lines: [String] = []
        lines.append("# \(conversation.title)")
        lines.append("")
        lines.append("**Project:** \(conversation.projectPath ?? "None")")
        lines.append("**Model:** \(conversation.modelChoice.rawValue)")
        lines.append("**Date:** \(conversation.createdAt.formatted())")
        lines.append("")
        lines.append("---")
        lines.append("")

        for msg in conversation.messages where !msg.isStreaming {
            let role = msg.role.rawValue.capitalized
            lines.append("### \(role)")
            lines.append("")
            lines.append(msg.content)
            lines.append("")

            if !msg.toolCalls.isEmpty {
                lines.append("**Tool calls:**")
                for call in msg.toolCalls {
                    lines.append("- `\(call.name)` — \(call.status.rawValue)")
                    if let result = call.result {
                        lines.append("  ```")
                        lines.append(String(result.prefix(200)))
                        lines.append("  ```")
                    }
                }
                lines.append("")
            }
        }

        if !conversation.fileChanges.isEmpty {
            lines.append("---")
            lines.append("")
            lines.append("### Files Modified")
            lines.append("")
            for change in conversation.fileChanges {
                lines.append("- [\(change.changeType.rawValue)] \(change.path)")
            }
        }

        return lines.joined(separator: "\n")
    }

    @MainActor
    static func save(_ conversation: Conversation) -> URL? {
        let markdown = exportAsMarkdown(conversation)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(conversation.title.replacingOccurrences(of: " ", with: "-")).md"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
