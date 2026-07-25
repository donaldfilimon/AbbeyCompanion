import SwiftUI

struct TerminalOutputView: View {
    let output: String
    let isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Terminal Output")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(height: 180)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
