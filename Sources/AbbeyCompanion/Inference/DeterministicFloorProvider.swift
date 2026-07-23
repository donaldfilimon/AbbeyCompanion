import Foundation
import AbbeyCore

/// The always-available fallback: no model call, no network, no on-device model load.
/// Uses `IntentClassifier` + small template banks keyed by persona register, so Abbey
/// never goes fully silent even with every model path unavailable.
struct DeterministicFloorProvider: InferenceProvider {
    let mode: InferenceMode = .deterministicFloor

    private static let acknowledgements = [
        "Got it.", "Noted.", "On it.", "Makes sense."
    ]

    func generate(_ request: InferenceRequest) async throws -> InferenceResult {
        let intent = IntentClassifier.classify(request.userText)
        let text: String
        switch intent {
        case .greeting:
            text = "Hey."
        case .question:
            let lastContextLine = request.contextLines.last(where: { !$0.isEmpty }) ?? "no recent channel context"
            text = "Running rule-based only. From context: \(lastContextLine)"
        case .command:
            text = "Command received. Use !help for the companion command list."
        case .modRequest:
            text = "Moderation request noted — ConfirmationGate handles execution."
        case .memoryStore:
            text = "I'll remember that."
        case .repQuery:
            text = "Ask with !rep [user] or ingest “what is my reputation?”."
        case .personaSwitch:
            text = "Persona switch noted."
        case .smallTalk:
            text = Self.acknowledgements.randomElement() ?? "Noted."
        case .unknown:
            text = "…"
        }
        return InferenceResult(text: text, mode: .deterministicFloor)
    }
}
