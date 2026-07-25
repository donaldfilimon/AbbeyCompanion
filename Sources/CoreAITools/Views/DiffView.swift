import SwiftUI

struct DiffView: View {
    let diffText: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text(line.prefix)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)

                        Text(line.content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(line.background)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private struct DiffLine {
        let prefix: String
        let content: String
        let color: Color
        let background: Color
    }

    private func parseLines() -> [DiffLine] {
        diffText.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return DiffLine(prefix: "+", content: String(line.dropFirst()), color: .green, background: Color.green.opacity(0.08))
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                return DiffLine(prefix: "-", content: String(line.dropFirst()), color: .red, background: Color.red.opacity(0.08))
            } else if line.hasPrefix("@@") {
                return DiffLine(prefix: " ", content: line, color: .blue, background: Color.blue.opacity(0.05))
            } else {
                return DiffLine(prefix: " ", content: line, color: .primary, background: .clear)
            }
        }
    }
}
