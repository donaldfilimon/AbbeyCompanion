import SwiftUI

struct QuickActionsBar: View {
    let store: ConversationStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                QuickActionButton(icon: "hammer", label: "Build", color: .blue, isDisabled: store.isStreaming) {
                    store.send("Build the project and report any errors")
                }
                QuickActionButton(icon: "checkmark.seal", label: "Test", color: .green, isDisabled: store.isStreaming) {
                    store.send("Run the test suite and report results")
                }
                QuickActionButton(icon: "branch", label: "Git Status", color: .orange, isDisabled: store.isStreaming) {
                    store.send("Show me the current git status")
                }
                QuickActionButton(icon: "doc.text.magnifyingglass", label: "Search", color: .purple, isDisabled: store.isStreaming) {
                    store.send("Search the codebase for key entry points and explain the architecture")
                }
                QuickActionButton(icon: "wand.and.stars", label: "Review", color: .indigo, isDisabled: store.isStreaming) {
                    store.send("Review the recent git diff and provide feedback on code quality")
                }
                QuickActionButton(icon: "bug", label: "Fix Errors", color: .red, isDisabled: store.isStreaming) {
                    store.send("Find and fix any build errors or failing tests in this project")
                }
                QuickActionButton(icon: "text.badge.plus", label: "Document", color: .teal, isDisabled: store.isStreaming) {
                    store.send("Generate or update documentation for this project")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
