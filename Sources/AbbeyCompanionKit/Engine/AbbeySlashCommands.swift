import Foundation

/// Bang/slash command surface for the companion ingest path (separate from CoreAITools slash commands).
@MainActor
enum AbbeySlashCommands {
    static func handle(
        _ text: String,
        authorId: String,
        guildId: String,
        personaRouter: ABIRouter,
        socialBrain: SocialBrain,
        scheduler: AbbeyScheduler,
        config: AppConfig,
        dqnStepCount: Int,
        mirrorSnapshot: () throws -> [String: Int]
    ) async -> PersonaResponse? {
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

    static func applyPersonaSwitchHint(from text: String, personaRouter: ABIRouter) async {
        let lower = text.lowercased()
        if lower.contains("aviva") {
            await personaRouter.setPersona(named: "aviva")
        } else if lower.contains("abi") {
            await personaRouter.setPersona(named: "abi")
        } else if lower.contains("abbey") {
            await personaRouter.setPersona(named: "abbey")
        }
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
}
