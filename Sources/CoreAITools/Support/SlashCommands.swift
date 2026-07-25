import Foundation

enum SlashCommand: String, CaseIterable {
    case clear
    case help
    case compact
    case git
    case files
    case model
    case explore
    case init_
    case stats

    var trigger: String { "/\(rawValue == "init_" ? "init" : rawValue)" }

    var description: String {
        switch self {
        case .clear: return "Clear the current conversation"
        case .help: return "Show available commands and tools"
        case .compact: return "Summarize conversation to save context"
        case .git: return "Show git status for the current project"
        case .files: return "Show modified files in this session"
        case .model: return "Show current model info"
        case .explore: return "Re-explore the project structure"
        case .init_: return "Generate a project context file (AGENTS.md)"
        case .stats: return "Show conversation statistics"
        }
    }

    static var helpText: String {
        var lines = ["**Available slash commands:**"]
        for cmd in allCases {
            lines.append("  `\(cmd.trigger)` — \(cmd.description)")
        }
        lines.append("")
        lines.append("**Tools available to the AI (19):**")
        lines.append("  `read_file` `write_file` `list_files` `search_code`")
        lines.append("  `run_command` `apply_edit` `project_structure`")
        lines.append("  `git_status` `git_diff` `git_log` `git_commit`")
        lines.append("  `git_branch` `git_push` `git_pull` `git_stash` `git_restore`\n  `git_add` `git_show` `git_remote`")
        lines.append("")
        lines.append("**Work modes:** Plan · Execute · Read-Only")
        lines.append("**Approval gates:** write, edit, command, git mutations")
        return lines.joined(separator: "\n")
    }

    static func parse(_ text: String) -> SlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let key = String(trimmed.dropFirst()).lowercased()
        if key == "init" { return .init_ }
        return SlashCommand(rawValue: key)
    }
}
