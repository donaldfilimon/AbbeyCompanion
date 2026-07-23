import Foundation

struct InferenceRequest: Sendable {
    var systemPrompt: String
    var userText: String
    var contextLines: [String]
}

struct InferenceResult: Sendable {
    var text: String
    var mode: InferenceMode
}

enum InferenceError: Error, LocalizedError {
    case providerUnavailable(InferenceMode)
    case remoteEndpointNotConfigured
    case remoteRequestFailed(statusCode: Int?, underlying: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let mode):
            return "Inference mode \(mode.rawValue) is unavailable on this machine."
        case .remoteEndpointNotConfigured:
            return "ABBEY_REMOTE_ENDPOINT is not set; configure it in Settings before using remoteCompatible mode."
        case .remoteRequestFailed(let statusCode, let underlying):
            return "Remote inference request failed (status: \(statusCode.map(String.init) ?? "n/a")): \(underlying)"
        case .decodingFailed(let detail):
            return "Could not decode inference response: \(detail)"
        }
    }
}

protocol InferenceProvider: Sendable {
    var mode: InferenceMode { get }
    func generate(_ request: InferenceRequest) async throws -> InferenceResult
}

/// Picks the right concrete provider given the current `AppConfig.inferenceMode` and
/// falls back to `DeterministicFloorProvider` on any failure, so a bad remote endpoint
/// or an unavailable on-device model never takes Abbey fully offline — it just degrades
/// to rule-based responses. Every fallback is reported through `EventBus` so the
/// Dashboard can surface it rather than hiding it.
package actor InferenceRouter {
    private let deterministicFloor: DeterministicFloorProvider
    private let onDevice: FoundationModelsProvider
    private let remote: RemoteOpenAICompatibleProvider
    private let eventBus: EventBus
    private let metrics: EngineMetrics
    private let currentMode: @Sendable () -> InferenceMode

    init(
        eventBus: EventBus,
        metrics: EngineMetrics,
        currentMode: @escaping @Sendable () -> InferenceMode,
        remoteEndpoint: @escaping @Sendable () -> String,
        remoteAPIKey: @escaping @Sendable () -> String = { "" },
        remoteModel: @escaping @Sendable () -> String = { "abbey-remote" }
    ) {
        self.deterministicFloor = DeterministicFloorProvider()
        self.onDevice = FoundationModelsProvider()
        self.remote = RemoteOpenAICompatibleProvider(
            endpointProvider: remoteEndpoint,
            apiKeyProvider: remoteAPIKey,
            modelProvider: remoteModel
        )
        self.eventBus = eventBus
        self.metrics = metrics
        self.currentMode = currentMode
    }

    func generate(_ request: InferenceRequest) async -> InferenceResult {
        let mode = currentMode()
        let provider: any InferenceProvider = {
            switch mode {
            case .deterministicFloor: return deterministicFloor
            case .onDevice: return onDevice
            case .remoteCompatible: return remote
            }
        }()

        do {
            let result = try await provider.generate(request)
            metrics.recordInferenceCall(mode: mode, succeeded: true)
            return result
        } catch {
            metrics.recordInferenceCall(mode: mode, succeeded: false)
            await eventBus.publish(.inferenceProviderFailed(mode: mode, message: error.localizedDescription))
            return (try? await deterministicFloor.generate(request))
                ?? InferenceResult(text: "", mode: .deterministicFloor)
        }
    }

    /// Direct probe of the configured remote endpoint (no fallback). Used by Settings.
    func probeRemote() async -> Result<String, Error> {
        do {
            let result = try await remote.generate(
                InferenceRequest(systemPrompt: "Reply with exactly: pong", userText: "ping", contextLines: [])
            )
            return .success(result.text)
        } catch {
            return .failure(error)
        }
    }
}
