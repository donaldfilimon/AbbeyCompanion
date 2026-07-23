import Foundation
import SwiftData

/// Owns the two time-driven behaviors described in /areas/abbey-bot.md:
///   - per-user reply cooldown (ABBEY_REPLY_COOLDOWN_SECONDS)
///   - channel memory consolidation on a fixed interval (ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN)
actor AbbeyScheduler {
    private var lastReplyAt: [String: Date] = [:]     // key: "guildId:userId"
    private var consolidationTask: Task<Void, Never>?

    private let modelContainer: ModelContainer
    private let eventBus: EventBus
    private let metrics: EngineMetrics
    private let inferenceRouter: InferenceRouter
    private let cooldownSeconds: @Sendable () -> Double
    private let consolidationIntervalMinutes: @Sendable () -> Double
    private let useAbstractive: @Sendable () -> Bool

    init(
        modelContainer: ModelContainer,
        eventBus: EventBus,
        metrics: EngineMetrics,
        inferenceRouter: InferenceRouter,
        cooldownSeconds: @escaping @Sendable () -> Double,
        consolidationIntervalMinutes: @escaping @Sendable () -> Double,
        useAbstractive: @escaping @Sendable () -> Bool
    ) {
        self.modelContainer = modelContainer
        self.eventBus = eventBus
        self.metrics = metrics
        self.inferenceRouter = inferenceRouter
        self.cooldownSeconds = cooldownSeconds
        self.consolidationIntervalMinutes = consolidationIntervalMinutes
        self.useAbstractive = useAbstractive
    }

    /// Returns `true` if the user is currently cooling down and Abbey should skip
    /// replying this turn. Does not itself record a new reply — call `markReplied`
    /// after actually sending one.
    func isCoolingDown(userId: String, guildId: String) -> Bool {
        guard let last = lastReplyAt[key(userId, guildId)] else { return false }
        return Date.now.timeIntervalSince(last) < cooldownSeconds()
    }

    /// Seconds remaining on cooldown, or `0` if clear.
    func cooldownRemaining(userId: String, guildId: String) -> TimeInterval {
        guard let last = lastReplyAt[key(userId, guildId)] else { return 0 }
        let remaining = cooldownSeconds() - Date.now.timeIntervalSince(last)
        return max(0, remaining)
    }

    func markReplied(userId: String, guildId: String) {
        lastReplyAt[key(userId, guildId)] = .now
    }

    /// Starts the recurring consolidation loop. Idempotent — calling this twice
    /// cancels the previous loop first, so config changes (interval edited in
    /// Settings) can just call `start()` again.
    func start() {
        consolidationTask?.cancel()
        consolidationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let intervalMinutes = self.consolidationIntervalMinutes()
                let nanoseconds = UInt64(max(intervalMinutes, 0.5) * 60 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self.consolidateAllChannels()
            }
        }
    }

    func stop() {
        consolidationTask?.cancel()
        consolidationTask = nil
    }

    /// Recomputes each `ChannelContext.summary`. Extractive (most-recent-N) by default;
    /// when `useAbstractive` is on and inference isn't the deterministic floor path's
    /// only option, asks `InferenceRouter` for a short abstractive summary (still
    /// falls back to extractive on empty/failure).
    func consolidateAllChannels() async {
        let context = ModelContext(modelContainer)
        guard let channels = try? context.fetch(FetchDescriptor<ChannelContext>()) else { return }
        let abstractive = useAbstractive()

        for channel in channels {
            let channelId = channel.channelId
            var descriptor = FetchDescriptor<GuildMessage>(
                predicate: #Predicate { $0.channelId == channelId }
            )
            descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
            descriptor.fetchLimit = 50
            guard let recent = try? context.fetch(descriptor), !recent.isEmpty else { continue }

            let summaryLines = recent.reversed().map { "\($0.authorId): \($0.content.prefix(120))" }
            let extractive = summaryLines.joined(separator: "\n")

            if abstractive {
                let result = await inferenceRouter.generate(
                    InferenceRequest(
                        systemPrompt: "Summarize this Discord channel transcript in 3 terse bullet lines. No preamble.",
                        userText: extractive,
                        contextLines: ["channel:#\(channelId)"]
                    )
                )
                channel.summary = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? extractive
                    : result.text
            } else {
                channel.summary = extractive
            }
            channel.messageCount = recent.count
            channel.updatedAt = .now

            await eventBus.publish(.channelContextConsolidated(channelId: channel.channelId, messageCount: recent.count))
        }

        try? context.save()
        metrics.recordConsolidation()
    }

    private func key(_ userId: String, _ guildId: String) -> String { "\(guildId):\(userId)" }
}
