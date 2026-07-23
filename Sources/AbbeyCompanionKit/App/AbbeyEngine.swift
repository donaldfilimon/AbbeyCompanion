import Foundation
import SwiftData
import Observation
import AbbeyCore

/// The single object the SwiftUI layer talks to. Owns the `ModelContainer` and every
/// actor described in the Engine/ and Inference/ folders.
@Observable
@MainActor
package final class AbbeyEngine {
    package let modelContainer: ModelContainer
    package let config = AppConfig.shared
    package let metrics = EngineMetrics()

    let eventBus: EventBus
    let socialBrain: SocialBrain
    let dqnAgent: DQNAgent
    package let scheduler: AbbeyScheduler
    let confirmationGate: ConfirmationGate
    let personaRouter: ABIRouter
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

    private var eventListenerTask: Task<Void, Never>?
    private let dqnCheckpointURL: URL

    package init(modelContainer: ModelContainer, dqnCheckpointURL: URL? = nil) {
        self.modelContainer = modelContainer
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
            let writeContext = ModelContext(modelContainer)
            let channel = upsertChannelContext(in: writeContext, channelId: channelId, guildId: guildId)
            writeContext.insert(
                GuildMessage(
                    discordMessageId: inboundMessageId,
                    channelId: channelId,
                    guildId: guildId,
                    authorId: authorId,
                    content: trimmed,
                    channel: channel
                )
            )
            try writeContext.save()
        } catch {
            succeeded = false
        }

        await eventBus.publish(.messageIngested(channelId: channelId, guildId: guildId, authorId: authorId))

        let reputationBefore = await socialBrain.reputation(userId: authorId, guildId: guildId)
        var userFacts = fetchUserFacts(userId: authorId, guildId: guildId)
        let channelSummary = fetchChannelSummary(channelId: channelId)
        let channelActivity = fetchChannelMessageCount(channelId: channelId)

        let intent = config.useStrictIntentClassification
            ? IntentClassifier.classifyStrict(trimmed)
            : IntentClassifier.classify(trimmed)
        lastIntent = intent

        if intent == .personaSwitch {
            await applyPersonaSwitchHint(from: trimmed)
        }
        if intent == .memoryStore {
            let fact = Self.extractMemoryFact(from: trimmed)
            await socialBrain.rememberFact(userId: authorId, guildId: guildId, fact: fact)
            userFacts = fetchUserFacts(userId: authorId, guildId: guildId)
        }

        // Chat-driven moderation: `!kick user reason` etc.
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
            await persistReply(response, channelId: channelId, guildId: guildId)
            lastReply = response
            logInteraction(command: "ingest:modRequest", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
            return response
        }

        if intent == .command, let slash = await handleSlashCommand(trimmed, authorId: authorId, guildId: guildId) {
            await persistReply(slash, channelId: channelId, guildId: guildId)
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
            authorInteractionCount: userFacts.count,
            isDirectMessage: false
        )
        let state = SentimentAnalyzer.projectToNetworkInput(state18)
        let actionIndex = await dqnAgent.selectAction(state: state)
        let dqnAction = DQNAction(raw: actionIndex)
        lastDQNAction = dqnAction
        attachPolicy(to: inboundMessageId, state: state, action: actionIndex)
        await dqnAgent.remember(Experience(state: state, action: actionIndex, reward: Float(intent.quality), nextState: state, done: true))
        await dqnAgent.learn(batchSize: 8)
        dqnStepCount = await dqnAgent.stepCount
        dqnExperienceCount = await dqnAgent.experienceCount
        await persistDQNCheckpoint()
        await socialBrain.recordInteraction(userId: authorId, guildId: guildId, quality: intent.quality)

        // Cooldown outranks DQN ignore so the UI/skip reason stays accurate.
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

        await persistReply(response, channelId: channelId, guildId: guildId)
        await scheduler.markReplied(userId: authorId, guildId: guildId)
        lastReply = response
        logInteraction(command: "ingest:\(intent.rawValue):\(dqnAction.label)", userId: authorId, guildId: guildId, succeeded: succeeded, started: started)
        return response
    }

    private func persistReply(_ response: PersonaResponse, channelId: String, guildId: String) async {
        do {
            let replyContext = ModelContext(modelContainer)
            let channel = upsertChannelContext(in: replyContext, channelId: channelId, guildId: guildId, incrementCount: false)
            replyContext.insert(
                GuildMessage(
                    discordMessageId: UUID().uuidString,
                    channelId: channelId,
                    guildId: guildId,
                    authorId: "abbey:\(response.personaName.lowercased())",
                    content: response.text,
                    channel: channel
                )
            )
            try replyContext.save()
        } catch {
            // Reply still surfaces via lastReply.
        }
    }

    package func logInteraction(command: String, userId: String, guildId: String, succeeded: Bool, started: ContinuousClock.Instant) {
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        let context = ModelContext(modelContainer)
        context.insert(
            InteractionLog(
                commandName: command,
                userId: userId,
                guildId: guildId,
                succeeded: succeeded,
                latencyMs: ms
            )
        )
        try? context.save()
    }

    private func applyPersonaSwitchHint(from text: String) async {
        let lower = text.lowercased()
        if lower.contains("aviva") {
            await personaRouter.setPersona(named: "aviva")
        } else if lower.contains("abi") {
            await personaRouter.setPersona(named: "abi")
        } else if lower.contains("abbey") {
            await personaRouter.setPersona(named: "abbey")
        }
    }

    /// Handles non-mod slash/bang commands: help, rep, persona, status, consolidate.
    private func handleSlashCommand(_ text: String, authorId: String, guildId: String) async -> PersonaResponse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!") || trimmed.hasPrefix("/") else { return nil }
        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let verb = parts.first?.lowercased() else { return nil }
        let persona = await personaRouter.currentPersona()

        switch verb {
        case "help", "commands":
            return PersonaResponse(
                text: """
                Commands: !help · !rep [user] · !persona [abbey|aviva|abi] · !status · !consolidate \
                · !kick|!ban|!purge <user> [reason]
                """,
                personaName: persona.name
            )
        case "rep", "reputation":
            let target = parts.count > 1 ? parts[1] : authorId
            let rep = await socialBrain.reputation(userId: target, guildId: guildId)
            return PersonaResponse(
                text: "Reputation for \(target) in \(guildId): \(String(format: "%.3f", rep)).",
                personaName: persona.name
            )
        case "persona":
            if parts.count > 1 {
                await personaRouter.setPersona(named: parts[1])
            }
            let active = await personaRouter.currentPersona()
            return PersonaResponse(text: "Active persona: \(active.name).", personaName: active.name)
        case "status":
            let remaining = await scheduler.cooldownRemaining(userId: authorId, guildId: guildId)
            let snap = (try? mirrorSnapshot()) ?? [:]
            return PersonaResponse(
                text: """
                mode=\(config.operatingMode.rawValue) inference=\(config.inferenceMode.rawValue) \
                persona=\(persona.name) dqnSteps=\(dqnStepCount) cooldown=\(String(format: "%.1f", remaining))s \
                store=\(snap)
                """,
                personaName: persona.name
            )
        case "consolidate":
            await scheduler.consolidateAllChannels()
            return PersonaResponse(text: "Channel consolidation triggered.", personaName: persona.name)
        default:
            return nil
        }
    }

    package func deleteMessage(_ message: GuildMessage) {
        let context = ModelContext(modelContainer)
        let id = message.discordMessageId
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == id })
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
            try? context.save()
        }
    }

    package func clearChannel(channelId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.channelId == channelId })
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
            try? context.save()
        }
    }

    package func deleteChannelContext(channelId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(predicate: #Predicate { $0.channelId == channelId })
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
            try? context.save()
        }
    }

    package func clearActivityLogs() {
        let context = ModelContext(modelContainer)
        try? context.delete(model: InteractionLog.self)
        try? context.save()
    }

    /// Wipes all SwiftData rows (keeps AppConfig / UserDefaults).
    package func resetLocalStore() throws {
        let context = ModelContext(modelContainer)
        try context.delete(model: GuildMessage.self)
        try context.delete(model: UserMemory.self)
        try context.delete(model: ChannelContext.self)
        try context.delete(model: ReputationEvent.self)
        try context.delete(model: InteractionLog.self)
        try context.delete(model: EquityIdea.self)
        try context.save()
        recentEvents.removeAll()
        lastReply = nil
        lastIntent = nil
        lastDQNAction = nil
        Task { await socialBrain.warmCache() }
    }

    static func extractMemoryFact(from text: String) -> String {
        let lower = text.lowercased()
        if let range = lower.range(of: "remember ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = lower.range(of: "note that ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
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
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        guard let user = try? context.fetch(descriptor).first else { return }
        user.facts.removeAll { $0 == fact }
        user.updatedAt = .now
        try? context.save()
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
        let context = ModelContext(modelContainer)
        let id = message.discordMessageId
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == id })
        guard let row = try? context.fetch(descriptor).first,
              row.hasPolicy,
              !row.hasPolicyReward
        else {
            return false
        }

        let state = row.policyState.map { Float($0) }
        let action = row.policyAction
        await dqnAgent.creditReward(state: state, action: action, reward: reward)
        dqnStepCount = await dqnAgent.stepCount
        dqnExperienceCount = await dqnAgent.experienceCount
        await persistDQNCheckpoint()

        row.reactionCount += reward >= 0 ? 1 : -1
        row.hasPolicyReward = true
        try? context.save()
        recentEvents.insert(
            "[\(Date.now.formatted(date: .omitted, time: .shortened))] reaction \(reward >= 0 ? "+" : "")\(String(format: "%.1f", reward)) on \(id.prefix(8))",
            at: 0
        )
        return true
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

    /// Mirror-mode helper: dump local store counts as a portable snapshot dictionary.
    package func mirrorSnapshot() throws -> [String: Int] {
        let context = ModelContext(modelContainer)
        return [
            "guildMessages": try context.fetchCount(FetchDescriptor<GuildMessage>()),
            "userMemories": try context.fetchCount(FetchDescriptor<UserMemory>()),
            "channelContexts": try context.fetchCount(FetchDescriptor<ChannelContext>()),
            "reputationEvents": try context.fetchCount(FetchDescriptor<ReputationEvent>()),
            "interactionLogs": try context.fetchCount(FetchDescriptor<InteractionLog>()),
            "equityIdeas": try context.fetchCount(FetchDescriptor<EquityIdea>())
        ]
    }

    /// Export a JSON document of messages + user memories for backup / mirror handoff.
    package func exportJSON() throws -> Data {
        let context = ModelContext(modelContainer)
        let messages = try context.fetch(FetchDescriptor<GuildMessage>(sortBy: [SortDescriptor(\.createdAt)]))
        let users = try context.fetch(FetchDescriptor<UserMemory>())
        let channels = try context.fetch(FetchDescriptor<ChannelContext>())

        let doc = MirrorExportDocument(
            messages: messages.map {
                .init(
                    discordMessageId: $0.discordMessageId,
                    channelId: $0.channelId,
                    guildId: $0.guildId,
                    authorId: $0.authorId,
                    content: $0.content,
                    createdAt: $0.createdAt
                )
            },
            users: users.map {
                .init(
                    discordUserId: $0.discordUserId,
                    guildId: $0.guildId,
                    facts: $0.facts,
                    reputation: $0.reputation,
                    interactionCount: $0.interactionCount
                )
            },
            channels: channels.map {
                .init(
                    channelId: $0.channelId,
                    guildId: $0.guildId,
                    summary: $0.summary,
                    messageCount: $0.messageCount
                )
            }
        )
        return try doc.encode()
    }

    /// Import messages/users/channels from `exportJSON` output (skips duplicate message IDs).
    package func importJSON(_ data: Data) throws -> (messages: Int, users: Int, channels: Int) {
        let doc = try MirrorExportDocument.decode(from: data)
        let context = ModelContext(modelContainer)
        var mCount = 0, uCount = 0, cCount = 0

        for msg in doc.messages {
            let id = msg.discordMessageId
            let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == id })
            if (try? context.fetch(descriptor).first) != nil { continue }
            let channel = upsertChannelContext(
                in: context,
                channelId: msg.channelId,
                guildId: msg.guildId,
                incrementCount: false
            )
            context.insert(
                GuildMessage(
                    discordMessageId: msg.discordMessageId,
                    channelId: msg.channelId,
                    guildId: msg.guildId,
                    authorId: msg.authorId,
                    content: msg.content,
                    createdAt: msg.createdAt,
                    channel: channel
                )
            )
            mCount += 1
        }
        for user in doc.users {
            let uid = user.discordUserId
            let gid = user.guildId
            let descriptor = FetchDescriptor<UserMemory>(
                predicate: #Predicate { $0.discordUserId == uid && $0.guildId == gid }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.facts = Array(Set(existing.facts + user.facts))
                existing.reputation = user.reputation
                existing.interactionCount = max(existing.interactionCount, user.interactionCount)
                existing.updatedAt = .now
            } else {
                context.insert(
                    UserMemory(
                        discordUserId: user.discordUserId,
                        guildId: user.guildId,
                        facts: user.facts,
                        reputation: user.reputation,
                        interactionCount: user.interactionCount
                    )
                )
                uCount += 1
            }
        }
        for channel in doc.channels {
            let cid = channel.channelId
            let descriptor = FetchDescriptor<ChannelContext>(predicate: #Predicate { $0.channelId == cid })
            if let existing = try? context.fetch(descriptor).first {
                if channel.summary.count > existing.summary.count { existing.summary = channel.summary }
                existing.messageCount = max(existing.messageCount, channel.messageCount)
                existing.updatedAt = .now
            } else {
                context.insert(
                    ChannelContext(
                        channelId: channel.channelId,
                        guildId: channel.guildId,
                        summary: channel.summary,
                        messageCount: channel.messageCount
                    )
                )
                cCount += 1
            }
        }
        try context.save()
        Task { await socialBrain.warmCache() }
        return (mCount, uCount, cCount)
    }

    private func attachPolicy(to messageId: String, state: [Float], action: Int) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GuildMessage>(predicate: #Predicate { $0.discordMessageId == messageId })
        guard let row = try? context.fetch(descriptor).first else { return }
        row.policyState = state.map { Double($0) }
        row.policyAction = action
        try? context.save()
    }

    @discardableResult
    private func upsertChannelContext(
        in context: ModelContext,
        channelId: String,
        guildId: String,
        incrementCount: Bool = true
    ) -> ChannelContext {
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        if let existing = try? context.fetch(descriptor).first {
            if incrementCount { existing.messageCount += 1 }
            existing.guildId = guildId
            existing.updatedAt = .now
            return existing
        }
        let created = ChannelContext(
            channelId: channelId,
            guildId: guildId,
            messageCount: incrementCount ? 1 : 0
        )
        context.insert(created)
        return created
    }

    private func fetchChannelSummary(channelId: String) -> String {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        return (try? context.fetch(descriptor).first?.summary) ?? ""
    }

    private func fetchChannelMessageCount(channelId: String) -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ChannelContext>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        return (try? context.fetch(descriptor).first?.messageCount) ?? 0
    }

    private func fetchUserFacts(userId: String, guildId: String) -> [String] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserMemory>(
            predicate: #Predicate { $0.discordUserId == userId && $0.guildId == guildId }
        )
        return (try? context.fetch(descriptor).first?.facts) ?? []
    }
}
