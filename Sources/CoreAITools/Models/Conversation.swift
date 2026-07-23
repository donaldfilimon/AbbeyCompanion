import Foundation

struct Conversation: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var projectPath: String?
    var createdAt: Date
    var updatedAt: Date
    var fileChanges: [FileChange]
    var modelChoice: ModelChoice
    var workMode: WorkMode

    enum ModelChoice: String, Codable, CaseIterable {
        case systemDefault = "On-Device (System)"
        case cloudCompute = "Private Cloud Compute"

        var description: String {
            switch self {
            case .systemDefault: return "SystemLanguageModel.default — runs entirely on-device"
            case .cloudCompute: return "PrivateCloudComputeLanguageModel — uses Apple's cloud for larger model"
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [ChatMessage] = [],
        projectPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        fileChanges: [FileChange] = [],
        modelChoice: ModelChoice = .systemDefault,
        workMode: WorkMode = .execute
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileChanges = fileChanges
        self.modelChoice = modelChoice
        self.workMode = workMode
    }
}
