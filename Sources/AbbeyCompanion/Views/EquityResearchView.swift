import SwiftUI
import SwiftData

struct EquityResearchView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EquityIdea.generatedAt, order: .reverse) private var ideas: [EquityIdea]

    var body: some View {
        VStack(spacing: 0) {
            disclaimerBanner

            if !engine.config.equityModuleEnabled {
                ContentUnavailableView(
                    "Equity module disabled",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Enable ABBEY_EQUITY_MODULE_ENABLED in Settings to generate synthetic ideas.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if ideas.isEmpty {
                    ContentUnavailableView(
                        "No synthetic ideas yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Generate ideas below. Every row is synthetic — not investment advice.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(ideas) { idea in
                        IdeaRow(idea: idea)
                    }
                }

                HStack {
                    Button("Generate one idea") { generate(count: 1) }
                    Button("Generate 5 ideas") { generate(count: 5) }
                    Spacer()
                    if !ideas.isEmpty {
                        Button("Clear all", role: .destructive) { clearIdeas() }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Equity Research")
    }

    private var disclaimerBanner: some View {
        Label(EquityIdea.disclaimer, systemImage: "info.circle")
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15))
    }

    private func generate(count: Int) {
        let started = ContinuousClock.now
        var engineCopy = engine.equityEngine
        let generated = engineCopy.generateBatch(count: count, context: modelContext)
        try? modelContext.save()
        engine.equityEngine = engineCopy
        for idea in generated {
            Task { await engine.eventBus.publish(.equityIdeaGenerated(symbol: idea.symbol)) }
        }
        engine.logInteraction(
            command: "equity:generate:\(count)",
            userId: "local",
            guildId: "companion",
            succeeded: !generated.isEmpty,
            started: started
        )
    }

    private func clearIdeas() {
        for idea in ideas {
            modelContext.delete(idea)
        }
        try? modelContext.save()
    }
}

private struct IdeaRow: View {
    let idea: EquityIdea

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(idea.symbol).font(.headline.monospaced())
                Spacer()
                Text("score \(String(format: "%.2f", idea.syntheticScore))")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(scoreColor(idea.syntheticScore).opacity(0.2), in: Capsule())
                    .foregroundStyle(scoreColor(idea.syntheticScore))
            }
            Text(idea.thesisSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !idea.factorBreakdown.isEmpty {
                Text(idea.factorBreakdown.keys.sorted().map {
                    "\($0): \(String(format: "%.2f", idea.factorBreakdown[$0] ?? 0))"
                }.joined(separator: " · "))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case ..<0.4: return .red
        case 0.4..<0.65: return .orange
        default: return .green
        }
    }
}
