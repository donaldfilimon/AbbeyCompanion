import Foundation
import SwiftData
import Observation
import AbbeyCore

/// Thin orchestrator: wires EventBus, SocialBrain, DQN, Scheduler, ConfirmationGate, personas, inference.
/// Persistence and slash commands live in dedicated types.
@Observable
@MainActor
package final class AbbeyEngine {
    package let modelContainer: ModelContainer
    package let config = AppConfig.shared
    package let metrics = EngineMetrics()
    package let persistence: AbbeyPersistence

    let eventBus: EventBus
    let socialBrain: SocialBrain
    let dqnAgent: DQNAgent
    package let scheduler: AbbeyScheduler
    let confirmationGate: ConfirmationGate
    package let personaRouter: ABIRouter
    let inferenceRouter: InferenceRouter
    var equityEngine = EquityResearchEngine()

    package private(set) var lastEvent: AbbeyEvent?
    package private(set) var confirmationTick: Int = 0
    package private(set) var lastReply: PersonaResponse?
    package private(set) var lastReplySkippedReason: String?
    package private(set) var lastIntent: IntentClassifier.Intent?
    package private(set) var lastDQNAction: DQNAction?
    package private(set) var dqnStepCount: Int = 0
    package private(set) var dqnExperienceCount: Int = 0
    package private(set) var lastBatchIngestCount: Int = 0
    /// Ring buffer of recent bus events for the Dashboard live feed.
    package private(set) var recentEvents: [String] = []
    /// Active pinned persona name (updated on `.personaSwitched`); drives AI assistant context refresh.
    package private(set) var activePersonaName: String = AbbeyPersona().name

    private var eventListenerTask: Task<Void, Never>?
    private let dqnCheckpointURL: URL

    package init(modelContainer: ModelContainer, dqnCheckpointURL: URL? = nil) {
        self.modelContainer = modelContainer
        self.persistence = AbbeyPersistence(modelContainer: modelContainer)
        self.dqnCheckpointURL = dqnCheckpointURL ?? Self.defaultDQNCheckpointURL()

        let bus = EventBus()
        self.eventBus = bus

        let config = AppConfig.shared
        self.socialBrain = SocialBrain(modelContainer: modelContainer, eventBus: bus, decay: { config.reputationDecay })
        self.dqnAgent = DQNAgent(topology: [SentimentAnalyzer.networkInputDimension, 32, 16, 3])
        self.confirmationGate = ConfirmationGate(eventBus: bus, requireConfirmation: { config.confirmationRequiredForDestructiveActions })
        self.personaRouter = ABIRouter(eventBus: bus)
        self.inferenceRouter = InferenceRouter(
            eventBus: bus,
            metrics: metrics,
            currentMode: { config.inferenceMode },
            remoteEndpoint: { config.remoteEndpoint },
            remoteAPIKey: { config.remoteAPIKey },
            remoteModel: { config.remoteModel }
        )
        self.scheduler = AbbeyScheduler(
            modelContainer: modelContainer,
            eventBus: bus,
            metrics: metrics,
            inferenceRouter: inferenceRouter,
            cooldownSeconds: { config.replyCooldownSeconds },
            consolidationIntervalMinutes: { config.memoryConsolidationIntervalMinutes },
            useAbstractive: { config.useAbstractiveConsolidation }
        )

        startEventListener()
        let checkpointURL = self.dqnCheckpointURL
        Task { [weak self, socialBrain, scheduler, dqnAgent] in
            await socialBrain.warmCache()
            await scheduler.start()
            await Self.loadDQNCheckpoint(into: dqnAgent, from: checkpointURL)
            guard let self else { return }
            self.dqnStepCount = await dqnAgent.stepCount
            self.dqnExperienceCount = await dqnAgent.experienceCount
        }
    }

    private static func defaultDQNCheckpointURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AbbeyCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dqn-checkpoint.json")
    }

    private static func loadDQNCheckpoint(into agent: DQNAgent, from url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let checkpoint = try JSONDecoder().decode(DQNAgent.Checkpoint.self, from: data)
            try await agent.loadCheckpoint(checkpoint)
        } catch {
            // Corrupt checkpoint — keep freshly initialized weights.
        }
    }

    private func persistDQNCheckpoint() async {
        do {
            let checkpoint = await dqnAgent.exportCheckpoint()
            let data = try JSONEncoder().encode(checkpoint)
            try data.write(to: dqnCheckpointURL, options: .atomic)
        } catch {
            // Persistence best-effort; runtime continues.
        }
    }

    private func startEventListener() {
        let bus = eventBus
        eventListenerTask = Task { [weak self] in
            let stream = await bus.subscribe()
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: AbbeyEvent) async {
        lastEvent = event
        recentEvents.insert(Self.describe(event), at: 0)
        if recentEvents.count > 40 { recentEvents = Array(recentEvents.prefix(40)) }

        switch event {
        case .messageIngested:
            metrics.recordMessageIngested()
        case .reputationChanged:
            metrics.recordReputationEvent()
        case .personaSwitched(let name):
            activePersonaName = name
        case .destructiveActionRequested:
            confirmationTick += 1
        case .destructiveActionConfirmed:
            metrics.recordDestructiveAction(confirmed: true)
        case .destructiveActionCancelled:
            metrics.recordDestructiveAction(confirmed: false)
        default:
            break
        }
    }

    private static func describe(_ event: AbbeyEvent) -> String {
        let stamp = Date.now.formatted(date: .omitted, time: .shortened)
        switch event {
        case .messageIngested(let channelId, _, let authorId):
            return "[\(stamp)] ingest #\(channelId) · \(authorId)"
        case .reputationChanged(let userId, _, let newValue, let reason):
            return "[\(stamp)] rep \(userId) → \(String(format: "%.3f", newValue)) (\(reason))"
        case .channelContextConsolidated(let channelId, let count):
            return "[\(stamp)] consolidate #\(channelId) · \(count) msgs"
        case .personaSwitched(let name):
            return "[\(stamp)] persona → \(name)"
        case .destructiveActionRequested(let kind, let user, _):
            return "[\(stamp)] confirm? \(kind.rawValue) \(user)"
        case .destructiveActionConfirmed(let kind, let user, _):
            return "[\(stamp)] confirmed \(kind.rawValue) \(user)"
        case .destructiveActionCancelled(let kind, let user):
            return "[\(stamp)] cancelled \(kind.rawValue) \(user)"
        case .equityIdeaGenerated(let symbol):
            return "[\(stamp)] equity \(symbol)"
        case .inferenceProviderFailed(let mode, let message):
            return "[\(stamp)] inference fail \(mode.rawValue): \(message)"
        }
    }

    /// Full standalone ingest loop with intent-specific side effects.
    @discardableResult
    package func ingestMessage(content: String, channelId: String, guildId: String, authorId: String) async -> PersonaResponse? {
        lastReplySkippedReason = nil
        lastReply = nil
        lastIntent = nil
        lastDQNAction = nil

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let started = ContinuousClock.now
        var succeeded = true

        let inboundMessageId = UUID().uuidString
        do {
            try persistence.insertInboundMessage(
                messageId: inboundMessageId,
                content: trimmed,
                channelId: channelId,
                guildId: guildId,
                authorId: authorId
            )
        } catch {
            succeeded = false
        }

        await eventBus.publish(.messageIngested(channelId: channelId, guildId: guildId, authorId: authorId))

        let reputationBefore = await socialBrain.reputation(userId: authorId, guildId: guildId)
        var userFacts = persistence.fetchUserFacts(userId: authorId, guildId: guildId)
        let channelSummary = persistence.fetchChannelSummary(channelId: channelId)
        let channelActivity = persistence.fetchChannelMessageCount(channelId: channelId)

        let intent = config.useStrictIntentClassification
            ? IntentClassifier.classifyStrict(trimmed)
            : IntentClassifier.classify(trimmed)
        lastIntent = intent

        if intent == .personaSwitch {
            await AbbeySlashCommands.applyPersonaSwitchHint(from: trimmed, personaRouter: personaRouter)
        }
        if intent == .memoryStore {
            let fact = AbbeySlashCommands.extractMemoryFact(from: trimmed)
            await socialBrain.rememberFact(userId: authorId, guildId: guildId, fact: fact)
            userFacts = persistence.fetchUserFacts(userId: authorId, guildId: guildId)
        }

        if intent == .modRequest, let parsed = IntentClassifier.parseModCommand(trimmed) {
            let kind = DestructiveAction(rawValue: parsed.kind) ?? .kick
            let brain = socialBrain
            await performDestructiveAction(kind, targetUserId: parsed.target, guildId: guildId, reason: parsed.reason) {
                await brain.penalize(
                    userId: parsed.target,
                    guildId: guildId,
                    reason: "\(parsed.kind): \(parsed.reason)"
                )
            }
            let persona = await personaRouter.route(intent: .modRequest)
            let response = PersonaResponse(
                text: "Moderation \(parsed.kind) for \(parsed.target) routed through ConfirmationGate.",
                personaName: persona.name
            )
            persistence.persistReply(response, channelId: channelId, guildId: guildId)
            lastReply = response
            logInteraction(command: "ingest:modRequest", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
            return response
        }

        if intent == .command,
           let slash = await AbbeySlashCommands.handle(
               trimmed,
               authorId: authorId,
               guildId: guildId,
               personaRouter: personaRouter,
               socialBrain: socialBrain,
               scheduler: scheduler,
               config: config,
               dqnStepCount: dqnStepCount,
               mirrorSnapshot: { [persistence] in try persistence.mirrorSnapshot() }
           ) {
            persistence.persistReply(slash, channelId: channelId, guildId: guildId)
            lastReply = slash
            logInteraction(command: "ingest:command", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
            return slash
        }

        let state18 = SentimentAnalyzer.analyze(
            text: trimmed,
            authorReputation: reputationBefore,
            recentReactionCount: 0,
            mentionsSomeone: trimmed.contains("@"),
            isReply: false,
            timestamp: .now,
            channelMessageCountInWindow: channelActivity,
            authorInteractionCount: persistence.fetchUserInteractionCount(userId: authorId, guildId: guildId),
            isDirectMessage: false
        )
        let state = SentimentAnalyzer.projectToNetworkInput(state18)
        let actionIndex = await dqnAgent.selectAction(state: state)
        let dqnAction = DQNAction(raw: actionIndex)
        lastDQNAction = dqnAction
        persistence.attachPolicy(to: inboundMessageId, state: state, action: actionIndex)
        await dqnAgent.remember(Experience(state: state, action: actionIndex, reward: Float(intent.quality), nextState: state, done: true))
        await dqnAgent.learn(batchSize: config.dqnBatchSize)
        dqnStepCount = await dqnAgent.stepCount
        dqnExperienceCount = await dqnAgent.experienceCount
        await persistDQNCheckpoint()
        await socialBrain.recordInteraction(userId: authorId, guildId: guildId, quality: intent.quality)

        if await scheduler.isCoolingDown(userId: authorId, guildId: guildId) {
            lastReplySkippedReason = "Reply cooldown active for \(authorId) in \(guildId)."
            logInteraction(command: "ingest:cooldown", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
            return nil
        }

        if dqnAction == .ignore {
            lastReplySkippedReason = "DQN chose ignore for this turn."
            logInteraction(command: "ingest:ignore", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
            return nil
        }

        let response: PersonaResponse
        if intent == .repQuery {
            let rep = await socialBrain.reputation(userId: authorId, guildId: guildId)
            let persona = await personaRouter.currentPersona()
            response = PersonaResponse(
                text: "Reputation for \(authorId) in \(guildId): \(String(format: "%.3f", rep)).",
                personaName: persona.name
            )
        } else if intent == .memoryStore {
            let persona = await personaRouter.currentPersona()
            response = PersonaResponse(
                text: "Noted. Stored fact for \(authorId).",
                personaName: persona.name
            )
        } else {
            var persona = await personaRouter.route(intent: intent)
            if dqnAction == .escalate {
                persona = AvivaPersona()
            }
            let personaContext = PersonaContext(
                channelSummary: channelSummary,
                userFacts: userFacts,
                reputation: reputationBefore
            )
            response = await persona.respond(to: trimmed, context: personaContext, inference: inferenceRouter)
        }

        persistence.persistReply(response, channelId: channelId, guildId: guildId)
        await scheduler.markReplied(userId: authorId, guildId: guildId)
        lastReply = response
        logInteraction(command: "ingest:\(intent.rawValue):\(dqnAction.label)", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
        return response
    }

    package func logInteraction(command: String, userId: String, guildId: String, succeeded: Bool, started: ContinuousClock.Instant) {
        persistence.logInteraction(command: command, userId: userId, guildId: guildId, succeeded: succeeded, started: started)
    }

    package func deleteMessage(_ message: GuildMessage) {
        persistence.deleteMessage(message)
    }

    package func clearChannel(channelId: String) {
        persistence.clearChannel(channelId: channelId)
    }

    package func deleteChannelContext(channelId: String) {
        persistence.deleteChannelContext(channelId: channelId)
    }

    package func clearActivityLogs() {
        persistence.clearActivityLogs()
    }

    /// Wipes all SwiftData rows (keeps AppConfig / UserDefaults).
    package func resetLocalStore() throws {
        try persistence.resetLocalStore()
        recentEvents.removeAll()
        lastReply = nil
        lastIntent = nil
        lastDQNAction = nil
        Task { await socialBrain.warmCache() }
    }

    package func performDestructiveAction(
        _ kind: DestructiveAction,
        targetUserId: String,
        guildId: String,
        reason: String,
        perform: @Sendable () async -> Void
    ) async {
        let started = ContinuousClock.now
        let approved = await confirmationGate.request(kind: kind, targetUserId: targetUserId, guildId: guildId, reason: reason)
        guard approved else {
            logInteraction(command: "mod:\(kind.rawValue)", userId: targetUserId, guildId: guildId, succeeded: false, started: started)
            return
        }
        await perform()
        logInteraction(command: "mod:\(kind.rawValue)", userId: targetUserId, guildId: guildId, succeeded: true, started: started)
    }

    package func removeFact(userId: String, guildId: String, fact: String) {
        persistence.removeFact(userId: userId, guildId: guildId, fact: fact)
    }

    package func addFact(userId: String, guildId: String, fact: String) async {
        await socialBrain.rememberFact(userId: userId, guildId: guildId, fact: fact)
    }

    /// Replay a multi-line transcript (one message per line; `#` comments and blanks skipped).
    @discardableResult
    package func ingestBatch(
        transcript: String,
        channelId: String,
        guildId: String,
        authorId: String
    ) async -> Int {
        let lines = transcript.split(whereSeparator: \.isNewline).map(String.init)
        var count = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            _ = await ingestMessage(
                content: trimmed,
                channelId: channelId,
                guildId: guildId,
                authorId: authorId
            )
            count += 1
        }
        lastBatchIngestCount = count
        return count
    }

    /// Apply a delayed 👍/👎 reward to the DQN decision recorded on an inbound message.
    @discardableResult
    package func applyReaction(to message: GuildMessage, reward: Float) async -> Bool {
        let id = message.discordMessageId
        guard let credited = persistence.applyReactionReward(to: id, reward: reward) else {
            return false
        }

        await dqnAgent.creditReward(state: credited.state, action: credited.action, reward: reward)
        dqnStepCount = await dqnAgent.stepCount
        dqnExperienceCount = await dqnAgent.experienceCount
        await persistDQNCheckpoint()

        recentEvents.insert(
            "[\(Date.now.formatted(date: .omitted, time: .shortened))] reaction \(reward >= 0 ? "+" : "")\(String(format: "%.1f", reward)) on \(id.prefix(8))",
            at: 0
        )
        return true
    }

    /// Push live DQN hyperparameters from AppConfig into the running agent.
    package func syncDQNConfig() async {
        await dqnAgent.updateHyperparameters(
            gamma: Float(config.dqnGamma),
            epsilon: Float(config.dqnEpsilon),
            learningRate: Float(config.dqnLearningRate),
            batchSize: config.dqnBatchSize
        )
    }

    /// Wipe persisted DQN weights and reinitialize in-memory agent from seed 42.
    package func resetDQNWeights() async {
        try? FileManager.default.removeItem(at: dqnCheckpointURL)
        await dqnAgent.reset(seed: 42)
        dqnStepCount = await dqnAgent.stepCount
        dqnExperienceCount = await dqnAgent.experienceCount
    }

    /// Seeds a small standalone demo so empty installs aren't blank.
    package func seedDemoData() async {
        let samples: [(String, String, String, String)] = [
            ("general", "dev-guild", "donald", "hey abbey"),
            ("general", "dev-guild", "donald", "remember I ship Zig nightlies"),
            ("general", "dev-guild", "alice", "what is my reputation?"),
            ("mods", "dev-guild", "donald", "switch to aviva"),
            ("mods", "dev-guild", "donald", "how should we structure permissions?")
        ]
        for sample in samples {
            await ingestMessage(content: sample.3, channelId: sample.0, guildId: sample.1, authorId: sample.2)
        }
    }

    package func mirrorSnapshot() throws -> [String: Int] {
        try persistence.mirrorSnapshot()
    }

    package func exportJSON() throws -> Data {
        try persistence.exportJSON()
    }

    package func importJSON(_ data: Data) throws -> (messages: Int, users: Int, channels: Int) {
        let counts = try persistence.importJSON(data)
        Task { await socialBrain.warmCache() }
        return counts
    }
}
