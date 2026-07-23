import Foundation
import FoundationModels

// MARK: - Run Command Tool (with approval)

struct RunCommandTool: Tool {
    @Generable(description: "Arguments for running a shell command")
    struct Arguments {
        @Guide(description: "The shell command to execute")
        var command: String
    }

    static let name = "run_command"
    let description = "Execute a shell command in the project directory and return stdout/stderr. Use for builds, tests, git, and other CLI operations."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        if let delegate = approvalDelegate {
            let approved = await delegate.requestApproval(
                toolName: "run_command",
                description: "Execute: \(arguments.command)"
            )
            if !approved {
                return "Error: User rejected command execution"
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", arguments.command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "<non-UTF8 output>"

        let exitCode = process.terminationStatus
        var result = output
        if exitCode != 0 {
            result += "\n[exit code: \(exitCode)]"
        }
        if result.count > 16_000 {
            return String(result.prefix(16_000)) + "\n\n… (truncated, \(result.count - 16_000) more characters)"
        }
        return result.isEmpty ? "[no output, exit code: \(exitCode)]" : result
    }
}

// MARK: - Apply Edit Tool (with approval)

struct ApplyEditTool: Tool {
    @Generable(description: "Arguments for applying a targeted edit to a file")
    struct Arguments {
        @Guide(description: "Path to the file to edit, relative to project root")
        var path: String
        @Guide(description: "The exact text to find in the file (must match exactly)")
        var findText: String
        @Guide(description: "The replacement text")
        var replaceText: String
    }

    static let name = "apply_edit"
    let description = "Find and replace a specific text block in a file. The findText must match exactly. Use for targeted code changes."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        if let delegate = approvalDelegate {
            let approved = await delegate.requestApproval(
                toolName: "apply_edit",
                description: "Edit \(arguments.path):\n  Find: \(String(arguments.findText.prefix(100)))\n  Replace: \(String(arguments.replaceText.prefix(100)))"
            )
            if !approved {
                return "Error: User rejected the edit to \(arguments.path)"
            }
        }

        guard let url = PathSecurity.resolve(within: workingDirectory, path: arguments.path) else {
            return PathSecurity.escapeError
        }
        let resolved = url.path

        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: File not found: \(resolved)"
        }

        let original = try String(contentsOfFile: resolved, encoding: .utf8)

        guard original.contains(arguments.findText) else {
            let lines = original.components(separatedBy: "\n")
            let preview = lines.prefix(5).joined(separator: "\n")
            return "Error: findText not found in file. First 5 lines:\n\(preview)"
        }

        // Replace every occurrence (not just the first) so multi-occurrence edits apply fully.
        let edited = original.replacingOccurrences(of: arguments.findText, with: arguments.replaceText)
        let replacedCount = original.components(separatedBy: arguments.findText).count - 1
        try edited.write(toFile: resolved, atomically: true, encoding: .utf8)

        return "Successfully edited \(arguments.path): replaced \(replacedCount) occurrence(s) of \(arguments.findText.count) chars with \(arguments.replaceText.count) chars"
    }
}
