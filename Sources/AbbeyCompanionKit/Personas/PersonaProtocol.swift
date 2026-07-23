import Foundation

package struct PersonaContext: Sendable {
    package var channelSummary: String
    package var userFacts: [String]
    package var reputation: Double
    package static let empty = PersonaContext(channelSummary: "", userFacts: [], reputation: 0.5)
}

package struct PersonaResponse: Sendable {
    package var text: String
    package var personaName: String
}

protocol Persona: Sendable {
    var name: String { get }
    var systemPrompt: String { get }
    func respond(to input: String, context: PersonaContext, inference: InferenceRouter) async -> PersonaResponse
}

extension Persona {
    func respond(to input: String, context: PersonaContext, inference: InferenceRouter) async -> PersonaResponse {
        let request = InferenceRequest(
            systemPrompt: systemPrompt,
            userText: input,
            contextLines: [context.channelSummary] + context.userFacts
        )
        let result = await inference.generate(request)
        return PersonaResponse(text: result.text, personaName: name)
    }
}
