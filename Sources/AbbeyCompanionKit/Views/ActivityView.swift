import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \InteractionLog.createdAt, order: .reverse) private var logs: [InteractionLog]

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Ingest messages, generate equity ideas, or run moderation actions to populate InteractionLog.")
                )
            } else {
                List(logs) { log in
                    HStack(alignment: .top) {
                        Image(systemName: log.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(log.succeeded ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.commandName).font(.headline.monospaced())
                            Text("\(log.userId) · \(log.guildId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1f ms", log.latencyMs))
                                .font(.caption.monospaced())
                            Text(log.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear log", role: .destructive) {
                    engine.clearActivityLogs()
                }
                .disabled(logs.isEmpty)
            }
        }
    }
}
