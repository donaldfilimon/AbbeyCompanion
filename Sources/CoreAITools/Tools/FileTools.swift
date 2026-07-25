import Foundation
import FoundationModels

// MARK: - Read File Tool

struct ReadFileTool: Tool {
    @Generable(description: "Arguments for reading a file")
    struct Arguments {
        @Guide(description: "Path to the file to read, relative to project root")
        var path: String
    }

    static let name = "read_file"
    let description = "Read the complete contents of a file at the given path within the project directory."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = PathSecurity.resolve(within: workingDirectory, path: arguments.path) else {
            return PathSecurity.escapeError
        }
        let resolved = url.path

        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: File not found at \(resolved)"
        }
        guard !url.hasDirectoryPath else {
            return "Error: \(resolved) is a directory, not a file"
        }

        // Guard against reading huge/binary files into memory.
        if let size = try? FileManager.default.attributesOfItem(atPath: resolved)[.size] as? UInt64,
           size > 5_000_000 {
            return "Error: file is too large to read (\(size) bytes)"
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: resolved))
        let content = String(data: data, encoding: .utf8) ?? "<binary file, \(data.count) bytes>"
        if content.count > 32_000 {
            return String(content.prefix(32_000)) + "\n\n… (truncated, \(content.count - 32_000) more characters)"
        }
        return content
    }
}

// MARK: - Write File Tool (with approval)

struct WriteFileTool: Tool {
    @Generable(description: "Arguments for writing a file")
    struct Arguments {
        @Guide(description: "Path to the file to write, relative to project root")
        var path: String
        @Guide(description: "The complete content to write to the file")
        var content: String
    }

    static let name = "write_file"
    let description = "Create or overwrite a file with the given content within the project directory."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        if let delegate = approvalDelegate {
            let preview = String(arguments.content.prefix(500))
            let approved = await delegate.requestApproval(
                toolName: "write_file",
                description: "Write \(arguments.content.count) chars to \(arguments.path)\n\nPreview:\n\(preview)"
            )
            if !approved {
                return "Error: User rejected the write operation to \(arguments.path)"
            }
        }

        guard let url = PathSecurity.resolve(within: workingDirectory, path: arguments.path) else {
            return PathSecurity.escapeError
        }
        let resolved = url.path

        let dir = (resolved as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try arguments.content.write(toFile: resolved, atomically: true, encoding: .utf8)
        return "Wrote \(arguments.content.count) characters to \(arguments.path)"
    }
}

// MARK: - List Files Tool

struct ListFilesTool: Tool {
    @Generable(description: "Arguments for listing files")
    struct Arguments {
        @Guide(description: "Directory path relative to project root. Defaults to project root if empty.")
        var path: String
    }

    static let name = "list_files"
    let description = "List files and directories at the given path within the project. Returns names with [DIR] prefix for directories."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        guard let baseURL = PathSecurity.resolve(within: workingDirectory, path: arguments.path.isEmpty ? "." : arguments.path) else {
            return PathSecurity.escapeError
        }
        let basePath = baseURL.path

        guard FileManager.default.fileExists(atPath: basePath) else {
            return "Error: Path not found: \(basePath)"
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: basePath)
        let sorted = contents.sorted()

        var lines: [String] = []
        for item in sorted {
            let fullPath = (basePath as NSString).appendingPathComponent(item)
            let isDir = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.type] as? FileAttributeType) == .typeDirectory
            lines.append(isDir ? "[DIR]  \(item)/" : "       \(item)")
        }

        return lines.joined(separator: "\n")
    }
}
