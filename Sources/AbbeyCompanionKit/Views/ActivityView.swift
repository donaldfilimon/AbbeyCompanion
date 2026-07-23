import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \InteractionLog.createdAt, order: .reverse) private var logs: [InteractionLog]
    @State private var search = ""

    private var filtered: [InteractionLog] {
        guard !search.isEmpty else { return logs }
        return logs.filter {
            $0.commandName.localizedCaseInsensitiveContains(search)
                || $0.userId.localizedCaseInsensitiveContains(search)
                || $0.guildId.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    logs.isEmpty ? "No activity yet" : "No matches",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        logs.isEmpty
                            ? "Ingest messages, generate equity ideas, or run moderation actions to populate InteractionLog."
                            : "Try a broader search."
                    )
                )
            } else {
                List(filtered) { log in
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
        .searchable(text: $search, prompt: "Command, user, or guild")
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

#Preview("Activity") {
    let engine = AbbeyStore.makePreviewEngine()
    return ActivityView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
