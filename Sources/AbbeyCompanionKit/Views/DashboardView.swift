import SwiftUI
import SwiftData
import AbbeyCore
import UniformTypeIdentifiers
import AppKit

struct DashboardView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query private var messages: [GuildMessage]
    @Query private var users: [UserMemory]
    @Query private var channels: [ChannelContext]
    @Query private var logs: [InteractionLog]

    @State private var draftChannelId = "general"
    @State private var draftGuildId = "dev-guild"
    @State private var draftAuthorId = "donald"
    @State private var draftContent = ""
    @State private var batchTranscript = ""
    @State private var isIngesting = false
    @State private var isBatching = false
    @State private var mirrorSnapshotText = ""
    @State private var ioStatus = ""

    private var completions: [String] {
        IntentClassifier.suggestCompletions(for: draftContent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    MetricCard(title: "Messages", value: "\(messages.count)")
                    MetricCard(title: "Users", value: "\(users.count)")
                    MetricCard(title: "Channels", value: "\(channels.count)")
                    MetricCard(title: "Session ingest", value: "\(engine.metrics.messagesIngestedThisSession)")
                    MetricCard(title: "Rep events", value: "\(engine.metrics.reputationEventsThisSession)")
                    MetricCard(title: "Inference calls", value: "\(engine.metrics.inferenceCallsByMode.values.reduce(0, +))")
                    MetricCard(title: "DQN steps", value: "\(engine.dqnStepCount)")
                    MetricCard(title: "DQN buffer", value: "\(engine.dqnExperienceCount)")
                    MetricCard(title: "Activity log", value: "\(logs.count)")
                }

                if engine.metrics.storeDegraded {
                    Label("Local store fell back to in-memory — data will not persist across launches.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                dataTools

                if engine.config.operatingMode == .mirror {
                    GroupBox("Mirror mode") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Same conceptual schema as the Vapor bot; Postgres sync is not implemented. Snapshot is local-only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Refresh local snapshot counts") { refreshMirrorSnapshot() }
                            if !mirrorSnapshotText.isEmpty {
                                Text(mirrorSnapshotText)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let failure = latestInferenceFailure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()
                ingestForm
                batchReplayForm

                HStack(spacing: 12) {
                    if let intent = engine.lastIntent {
                        Text("intent: \(intent.rawValue)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let action = engine.lastDQNAction {
                        Text("dqn: \(action.label)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let reply = engine.lastReply {
                    GroupBox("Last Abbey reply · \(reply.personaName)") {
                        Text(reply.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if let skip = engine.lastReplySkippedReason {
                    Label(skip, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }

                if !engine.recentEvents.isEmpty {
                    GroupBox("Live event feed") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(engine.recentEvents.prefix(12), id: \.self) { line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if messages.isEmpty {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Seed demo data, or try: hi · remember I use Zig · !kick spammy toxic · switch to aviva")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                }

                if !ioStatus.isEmpty {
                    Text(ioStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onAppear { if engine.config.operatingMode == .mirror { refreshMirrorSnapshot() } }
    }

    private var latestInferenceFailure: String? {
        if case .inferenceProviderFailed(_, let message) = engine.lastEvent {
            return message
        }
        return nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Standalone companion loop")
                .font(.title2.bold())
            Text("Mode: \(engine.config.operatingMode.rawValue) · Inference: \(engine.config.inferenceMode.rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dataTools: some View {
        HStack {
            Button("Seed demo data") {
                Task {
                    await engine.seedDemoData()
                    ioStatus = "Seeded demo messages."
                    if engine.config.operatingMode == .mirror { refreshMirrorSnapshot() }
                }
            }
            Button("Export JSON…") { exportJSON() }
            Button("Import JSON…") { importJSON() }
            Spacer()
        }
    }

    private var ingestForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulate a message").font(.headline)
            HStack {
                TextField("Channel ID", text: $draftChannelId)
                TextField("Guild ID", text: $draftGuildId)
                TextField("Author ID", text: $draftAuthorId)
            }
            .textFieldStyle(.roundedBorder)

            TextField("Message content", text: $draftContent, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .onSubmit { Task { await ingest() } }

            if !completions.isEmpty && !draftContent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(completions.prefix(6), id: \.self) { suggestion in
                            Button(suggestion) { draftContent = suggestion }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                Button {
                    Task { await ingest() }
                } label: {
                    if isIngesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Ingest & reply")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isIngesting)
                .keyboardShortcut(.return, modifiers: [.command])

                Spacer()
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private var batchReplayForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batch transcript replay").font(.headline)
            Text("One message per line. Lines starting with # are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $batchTranscript)
                .font(.body.monospaced())
                .frame(minHeight: 88, maxHeight: 160)
                .border(.quaternary)

            HStack {
                Button {
                    Task { await replayBatch() }
                } label: {
                    if isBatching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Replay transcript")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    batchTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBatching
                )
                Spacer()
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func ingest() async {
        isIngesting = true
        defer { isIngesting = false }
        await engine.ingestMessage(
            content: draftContent,
            channelId: draftChannelId,
            guildId: draftGuildId,
            authorId: draftAuthorId
        )
        draftContent = ""
        if engine.config.operatingMode == .mirror { refreshMirrorSnapshot() }
    }

    private func replayBatch() async {
        isBatching = true
        defer { isBatching = false }
        let count = await engine.ingestBatch(
            transcript: batchTranscript,
            channelId: draftChannelId,
            guildId: draftGuildId,
            authorId: draftAuthorId
        )
        ioStatus = "Replayed \(count) transcript line(s)."
        if engine.config.operatingMode == .mirror { refreshMirrorSnapshot() }
    }

    private func refreshMirrorSnapshot() {
        do {
            let snap = try engine.mirrorSnapshot()
            mirrorSnapshotText = snap.keys.sorted().map { "\($0): \(snap[$0] ?? 0)" }.joined(separator: "\n")
        } catch {
            mirrorSnapshotText = "snapshot failed: \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        do {
            let data = try engine.exportJSON()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "abbey-companion-export.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            ioStatus = "Exported to \(url.lastPathComponent)"
        } catch {
            ioStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let result = try engine.importJSON(data)
            ioStatus = "Imported +\(result.messages) msgs, +\(result.users) users, +\(result.channels) channels"
            if engine.config.operatingMode == .mirror { refreshMirrorSnapshot() }
        } catch {
            ioStatus = "Import failed: \(error.localizedDescription)"
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}
