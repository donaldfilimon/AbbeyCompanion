import SwiftUI

struct ApprovalBannerView: View {
    let gate: ApprovalGate

    var body: some View {
        if let pending = gate.pendingRequest {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approval Required")
                            .font(.headline)
                        Text("\(pending.toolName)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reject") {
                        gate.reject()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .keyboardShortcut(.cancelAction)

                    Button("Approve") {
                        gate.approve()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(pending.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
