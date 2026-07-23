import SwiftUI

struct ToolCallView: View {
    let toolCall: ToolCallRecord

    var body: some View {
        DisclosureGroup {
            if let result = toolCall.result {
                if isDiffOutput {
                    DiffView(diffText: result)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("No output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(toolCall.name)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                StatusBadge(status: toolCall.status)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // Detect if the output looks like a diff (has +/-/@@ lines)
    private var isDiffOutput: Bool {
        guard let result = toolCall.result else { return false }
        return toolCall.name == "git_diff" ||
               result.contains("@@ -") && result.contains("+++") ||
               (result.contains("\n+") && result.contains("\n-"))
    }

    private var toolIcon: String {
        switch toolCall.name {
        case "read_file": return "doc.text"
        case "write_file": return "doc.badge.plus"
        case "list_files": return "folder"
        case "search_code": return "magnifyingglass"
        case "run_command": return "terminal"
        case "apply_edit": return "pencil.line"
        case "project_structure": return "list.bullet.indent"
        case "git_status": return "checkmark.circle"
        case "git_diff": return "rectangle.split.2x1"
        case "git_log": return "clock.arrow.circlepath"
        case "git_commit": return "arrow.triangle.circlepath"
        case "git_branch": return "branch"
        case "git_push": return "arrow.up.circle"
        case "git_pull": return "arrow.down.circle"
        case "git_stash": return "tray.and.arrow.down"
        case "git_restore": return "arrow.uturn.backward"
        default: return "wrench.and.screwdriver"
        }
    }
}

private struct StatusBadge: View {
    let status: ToolCallRecord.Status

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .awaitingApproval: return .yellow
        case .rejected: return .gray
        }
    }
}
