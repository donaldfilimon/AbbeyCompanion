import SwiftUI

struct CommandHistoryView: View {
    let messages: [ChatMessage]

    private var commandEntries: [CommandEntry] {
        messages.flatMap { msg in
            msg.toolCalls.filter { $0.name == "run_command" }.compactMap { call in
                CommandEntry(
                    command: call.argumentsSummary,
                    result: call.result ?? "(no output)",
                    timestamp: msg.timestamp
                )
            }
        }
    }

    var body: some View {
        if commandEntries.isEmpty {
            Text("No commands run yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(12)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(commandEntries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "terminal")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.command)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(entry.result)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(8)
            }
        }
    }

    private struct CommandEntry {
        let command: String
        let result: String
        let timestamp: Date
    }
}
