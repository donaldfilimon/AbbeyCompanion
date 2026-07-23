import Foundation

enum OperatingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case standalone
    case mirror
    var id: String { rawValue }
}

enum InferenceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case deterministicFloor   // no model calls at all — rule-based only
    case onDevice             // Foundation Models framework, on-device
    case remoteCompatible     // OpenAI-compatible HTTP endpoint over URLSession
    var id: String { rawValue }
}

/// The ABBEY_* configuration knobs, mirrored from the bot's environment-variable
/// surface so the companion app's Settings screen edits the *same conceptual switches*
/// Donald already has muscle memory for from the Vapor deployment's `.env`.
///
/// Persisted via `UserDefaults` (per-machine, not synced) rather than SwiftData, since
/// these are process configuration, not domain data.
@Observable
final class AppConfig: @unchecked Sendable {
    /// Process-wide settings singleton. `@unchecked Sendable` + shared instance is
    /// intentional: actors read these knobs via sync closures, and UserDefaults is
    /// the synchronization boundary.
    static let shared = AppConfig()

    private let defaults: UserDefaults

    // ABBEY_OPERATING_MODE
    var operatingMode: OperatingMode {
        didSet { defaults.set(operatingMode.rawValue, forKey: Keys.operatingMode) }
    }
    // ABBEY_INFERENCE_MODE
    var inferenceMode: InferenceMode {
        didSet { defaults.set(inferenceMode.rawValue, forKey: Keys.inferenceMode) }
    }
    // ABBEY_REMOTE_ENDPOINT — only consulted when inferenceMode == .remoteCompatible
    var remoteEndpoint: String {
        didSet { defaults.set(remoteEndpoint, forKey: Keys.remoteEndpoint) }
    }
    // ABBEY_REMOTE_API_KEY — optional Bearer token for OpenAI-compatible endpoints
    var remoteAPIKey: String {
        didSet { defaults.set(remoteAPIKey, forKey: Keys.remoteAPIKey) }
    }
    // ABBEY_REMOTE_MODEL — model id sent in chat/completions body
    var remoteModel: String {
        didSet { defaults.set(remoteModel, forKey: Keys.remoteModel) }
    }
    // ABBEY_REPLY_COOLDOWN_SECONDS — per-user reply cooldown enforced by AbbeyScheduler
    var replyCooldownSeconds: Double {
        didSet { defaults.set(replyCooldownSeconds, forKey: Keys.replyCooldownSeconds) }
    }
    // ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN — how often ChannelContext summaries recompute
    var memoryConsolidationIntervalMinutes: Double {
        didSet { defaults.set(memoryConsolidationIntervalMinutes, forKey: Keys.consolidationInterval) }
    }
    // ABBEY_REPUTATION_DECAY — EMA weight applied to the existing score in SocialBrain
    var reputationDecay: Double {
        didSet { defaults.set(reputationDecay, forKey: Keys.reputationDecay) }
    }
    // ABBEY_CONFIRMATION_REQUIRED — gates purge/kick/ban behind ConfirmationGate
    var confirmationRequiredForDestructiveActions: Bool {
        didSet { defaults.set(confirmationRequiredForDestructiveActions, forKey: Keys.confirmationRequired) }
    }
    // ABBEY_EQUITY_MODULE_ENABLED — the synthetic/not-advice equity research surface
    var equityModuleEnabled: Bool {
        didSet { defaults.set(equityModuleEnabled, forKey: Keys.equityModuleEnabled) }
    }
    // ABBEY_USE_STRICT_INTENT — opt into classifyStrict (unknown for tiny/non-letter input)
    var useStrictIntentClassification: Bool {
        didSet { defaults.set(useStrictIntentClassification, forKey: Keys.strictIntent) }
    }
    // ABBEY_ABSTRACTIVE_CONSOLIDATION — use inference for channel summaries when not on floor
    var useAbstractiveConsolidation: Bool {
        didSet { defaults.set(useAbstractiveConsolidation, forKey: Keys.abstractiveConsolidation) }
    }

    private enum Keys {
        static let operatingMode = "ABBEY_OPERATING_MODE"
        static let inferenceMode = "ABBEY_INFERENCE_MODE"
        static let remoteEndpoint = "ABBEY_REMOTE_ENDPOINT"
        static let remoteAPIKey = "ABBEY_REMOTE_API_KEY"
        static let remoteModel = "ABBEY_REMOTE_MODEL"
        static let replyCooldownSeconds = "ABBEY_REPLY_COOLDOWN_SECONDS"
        static let consolidationInterval = "ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN"
        static let reputationDecay = "ABBEY_REPUTATION_DECAY"
        static let confirmationRequired = "ABBEY_CONFIRMATION_REQUIRED"
        static let equityModuleEnabled = "ABBEY_EQUITY_MODULE_ENABLED"
        static let strictIntent = "ABBEY_USE_STRICT_INTENT"
        static let abstractiveConsolidation = "ABBEY_ABSTRACTIVE_CONSOLIDATION"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.operatingMode = OperatingMode(rawValue: defaults.string(forKey: Keys.operatingMode) ?? "") ?? .standalone
        self.inferenceMode = InferenceMode(rawValue: defaults.string(forKey: Keys.inferenceMode) ?? "") ?? .deterministicFloor
        self.remoteEndpoint = defaults.string(forKey: Keys.remoteEndpoint) ?? ""
        self.remoteAPIKey = defaults.string(forKey: Keys.remoteAPIKey) ?? ""
        self.remoteModel = defaults.string(forKey: Keys.remoteModel) ?? "abbey-remote"
        let cooldown = defaults.double(forKey: Keys.replyCooldownSeconds)
        self.replyCooldownSeconds = cooldown > 0 ? cooldown : 8.0
        let interval = defaults.double(forKey: Keys.consolidationInterval)
        self.memoryConsolidationIntervalMinutes = interval > 0 ? interval : 15.0
        let decay = defaults.double(forKey: Keys.reputationDecay)
        self.reputationDecay = decay > 0 ? decay : 0.95
        self.confirmationRequiredForDestructiveActions = defaults.object(forKey: Keys.confirmationRequired) as? Bool ?? true
        self.equityModuleEnabled = defaults.object(forKey: Keys.equityModuleEnabled) as? Bool ?? true
        self.useStrictIntentClassification = defaults.object(forKey: Keys.strictIntent) as? Bool ?? false
        self.useAbstractiveConsolidation = defaults.object(forKey: Keys.abstractiveConsolidation) as? Bool ?? false
    }
}
