import SwiftUI

struct StatusBarView: View {
    let store: ConversationStore

    var body: some View {
        HStack(spacing: 12) {
            // Model status
            Circle()
                .fill(store.ai.isAvailable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(store.ai.availabilityMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            // Model choice
            if let convo = store.selectedConversation {
                Text(convo.modelChoice.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Capabilities (macOS 27+)
            if !store.ai.modelCapabilities.isEmpty {
                Divider().frame(height: 12)
                Text(store.ai.modelCapabilities.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .frame(height: 12)

            // Token usage
            if store.ai.contextWindowUsed > 0 {
                Text("ctx: \(store.ai.contextWindowUsed) tok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // File changes
            if !store.fileChanges.isEmpty {
                Divider().frame(height: 12)
                Text("\(store.fileChanges.count) files changed")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Approval status
            if store.ai.approvalGate.isApprovalEnabled {
                Divider().frame(height: 12)
                Image(systemName: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Approval on")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Streaming indicator
            if store.isStreaming {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Generating…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .coreAIGlass()
    }
}
