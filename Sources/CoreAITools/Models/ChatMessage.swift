import Foundation

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var role: Role
    var content: String
    var toolCalls: [ToolCallRecord]
    var timestamp: Date
    var isStreaming: Bool

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        toolCalls: [ToolCallRecord] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

struct ToolCallRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let argumentsSummary: String
    var result: String?
    var status: Status
    var requiresApproval: Bool
    var isApproved: Bool

    enum Status: String, Codable {
        case pending
        case running
        case completed
        case failed
        case awaitingApproval
        case rejected
    }

    init(
        id: UUID = UUID(),
        name: String,
        argumentsSummary: String,
        result: String? = nil,
        status: Status = .pending,
        requiresApproval: Bool = false,
        isApproved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.argumentsSummary = argumentsSummary
        self.result = result
        self.status = status
        self.requiresApproval = requiresApproval
        self.isApproved = isApproved
    }

    static var approvalRequiredTools: Set<String> {
        ["write_file", "apply_edit", "run_command", "git_commit"]
    }
}

struct FileChange: Identifiable, Hashable, Codable {
    let id: UUID
    let path: String
    let changeType: ChangeType
    let timestamp: Date

    enum ChangeType: String, Codable {
        case created
        case modified
        case deleted
    }

    init(id: UUID = UUID(), path: String, changeType: ChangeType, timestamp: Date = Date()) {
        self.id = id
        self.path = path
        self.changeType = changeType
        self.timestamp = timestamp
    }
}
