import Testing
@testable import CoreAITools

struct WorkModeTests {
    @Test func workMode_allCases() {
        #expect(WorkMode.allCases.count == 3)
        #expect(WorkMode.allCases.contains(.plan))
        #expect(WorkMode.allCases.contains(.execute))
        #expect(WorkMode.allCases.contains(.readOnly))
    }

    @Test func workMode_icons() {
        #expect(WorkMode.plan.icon == "list.clipboard")
        #expect(WorkMode.execute.icon == "bolt.fill")
        #expect(WorkMode.readOnly.icon == "eye")
    }

    @Test func systemPrompt_containsProjectPath() {
        let prompt = SystemPrompt.instructions(for: "/test/project")
        #expect(prompt.contains("/test/project"))
    }

    @Test func systemPrompt_planMode_containsPlanInstructions() {
        let prompt = SystemPrompt.instructions(for: "/test", mode: .plan)
        #expect(prompt.contains("PLAN MODE"))
    }

    @Test func systemPrompt_executeMode_containsGuidelines() {
        let prompt = SystemPrompt.instructions(for: "/test", mode: .execute)
        #expect(prompt.contains("Guidelines"))
    }

    @Test func systemPrompt_readOnlyMode_containsReadOnly() {
        let prompt = SystemPrompt.instructions(for: "/test", mode: .readOnly)
        #expect(prompt.contains("READ-ONLY"))
    }
}
