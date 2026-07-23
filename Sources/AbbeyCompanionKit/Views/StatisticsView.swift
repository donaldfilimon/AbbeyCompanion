import SwiftUI
import SwiftData
import AbbeyCore

package struct StatisticsView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \InteractionLog.createdAt, order: .reverse) private var logs: [InteractionLog]
    @Query private var allMessages: [GuildMessage]
    @Query private var allUsers: [UserMemory]

    package init() {}

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                dqnSection
                inferenceSection
                sessionSection
                messageActivitySection
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Training & Session Metrics")
                .font(.title2.bold())
            Text("DQN learning progress, inference breakdown, and session activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dqnSection: some View {
        GroupBox("DQN Agent") {
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Steps", value: "\(engine.dqnStepCount)")
                StatRow(label: "Replay buffer", value: "\(engine.dqnExperienceCount)")
                StatRow(label: "Last batch ingest", value: "\(engine.lastBatchIngestCount)")
                if let action = engine.lastDQNAction {
                    StatRow(label: "Last action", value: action.label)
                }
                if let intent = engine.lastIntent {
                    StatRow(label: "Last intent", value: intent.rawValue)
                }
                StatRow(label: "Gamma", value: String(format: "%.3f", engine.config.dqnGamma))
                StatRow(label: "Epsilon", value: String(format: "%.2f", engine.config.dqnEpsilon))
                StatRow(label: "Topology", value: "8 → 32 → 16 → 3")

                Divider()

                Text("Action distribution")
                    .font(.caption.weight(.semibold))
                ActionDistributionBar(messages: allMessages)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inferenceSection: some View {
        GroupBox("Inference") {
            VStack(alignment: .leading, spacing: 10) {
                let calls = engine.metrics.inferenceCallsByMode
                let total = calls.values.reduce(0, +)
                StatRow(label: "Total calls", value: "\(total)")

                ForEach(InferenceMode.allCases, id: \.rawValue) { mode in
                    let count = calls[mode] ?? 0
                    if count > 0 {
                        HStack {
                            Text(mode.rawValue)
                                .font(.caption.monospaced())
                            Spacer()
                            Text("\(count)")
                                .font(.caption.monospaced())
                            if total > 0 {
                                ProgressView(value: Double(count), total: Double(total))
                                    .frame(width: 80)
                            }
                        }
                    }
                }

                let failures = engine.metrics.inferenceFailuresByMode
                let totalFailures = failures.values.reduce(0, +)
                if totalFailures > 0 {
                    Divider()
                    StatRow(label: "Failures", value: "\(totalFailures)", color: .red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sessionSection: some View {
        GroupBox("Session") {
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Messages ingested", value: "\(engine.metrics.messagesIngestedThisSession)")
                StatRow(label: "Reputation events", value: "\(engine.metrics.reputationEventsThisSession)")
                StatRow(label: "Destructive confirmed", value: "\(engine.metrics.destructiveActionsConfirmed)")
                StatRow(label: "Destructive cancelled", value: "\(engine.metrics.destructiveActionsCancelled)")
                if let consolidated = engine.metrics.lastConsolidationAt {
                    StatRow(label: "Last consolidation", value: consolidated.formatted(date: .omitted, time: .shortened))
                }
                if engine.metrics.storeDegraded {
                    StatRow(label: "Store", value: "in-memory fallback", color: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var messageActivitySection: some View {
        GroupBox("Message Activity") {
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Total messages", value: "\(allMessages.count)")
                StatRow(label: "Messages with policy", value: "\(allMessages.filter(\.hasPolicy).count)")
                StatRow(label: "Messages rewarded", value: "\(allMessages.filter(\.hasPolicyReward).count)")
                StatRow(label: "Total users", value: "\(allUsers.count)")
                StatRow(label: "Activity log entries", value: "\(logs.count)")

                if !logs.isEmpty {
                    Divider()
                    Text("Recent activity")
                        .font(.caption.weight(.semibold))
                    let succeeded = logs.filter(\.succeeded).count
                    let successRate = Double(succeeded) / Double(logs.count) * 100
                    StatRow(label: "Success rate", value: String(format: "%.1f%%", successRate))
                    let avgLatency = logs.map(\.latencyMs).reduce(0, +) / Double(logs.count)
                    StatRow(label: "Avg latency", value: String(format: "%.1f ms", avgLatency))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(color)
        }
    }
}

private struct ActionDistributionBar: View {
    let messages: [GuildMessage]

    private var distribution: [(DQNAction, Int, Double)] {
        let total = messages.filter(\.hasPolicy).count
        guard total > 0 else { return [] }
        return DQNAction.allCases.map { action in
            let count = messages.filter { $0.policyAction == action.rawValue }.count
            let pct = Double(count) / Double(total) * 100
            return (action, count, pct)
        }
    }

    var body: some View {
        if distribution.isEmpty {
            Text("No policy decisions recorded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(distribution, id: \.0.rawValue) { action, count, pct in
                    HStack {
                        Text(action.label)
                            .font(.caption2.monospaced())
                            .frame(width: 60, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor(for: action))
                                .frame(width: max(geo.size.width * (pct / 100), 2))
                        }
                        .frame(height: 12)
                        Text("\(count) (\(String(format: "%.0f%%", pct)))")
                            .font(.caption2.monospaced())
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func barColor(for action: DQNAction) -> Color {
        switch action {
        case .ignore: return .gray
        case .reply: return .green
        case .escalate: return .orange
        }
    }
}
