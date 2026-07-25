import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device inference via Apple's Foundation Models framework.
///
/// Verified against the macOS 27 / Xcode 27 beta SDK (`SystemLanguageModel`,
/// `LanguageModelSession.respond(to:) -> Response<String>.content`, and
/// `Availability.unavailable(UnavailableReason)`). Still falls back through
/// `InferenceRouter` if the model is unavailable at runtime.
struct FoundationModelsProvider: InferenceProvider {
    let mode: InferenceMode = .onDevice

    func generate(_ request: InferenceRequest) async throws -> InferenceResult {
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, *) else {
            throw InferenceError.providerUnavailable(.onDevice)
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw InferenceError.remoteRequestFailed(
                statusCode: nil,
                underlying: "Foundation Models unavailable: \(String(describing: reason))"
            )
        @unknown default:
            throw InferenceError.providerUnavailable(.onDevice)
        }

        let session = LanguageModelSession(model: model, instructions: request.systemPrompt)
        let prompt = (request.contextLines + [request.userText])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        do {
            let response = try await session.respond(to: prompt)
            return InferenceResult(text: response.content, mode: .onDevice)
        } catch {
            throw InferenceError.remoteRequestFailed(statusCode: nil, underlying: String(describing: error))
        }
        #else
        throw InferenceError.providerUnavailable(.onDevice)
        #endif
    }
}
