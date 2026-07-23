import Foundation
import FoundationModels

// MARK: - Shared Git Runner

enum GitRunner {
    static func run(_ args: [String], workingDirectory: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if process.isRunning { process.terminate() }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.isEmpty {
            return "[git \(args.joined(separator: " ")) — no output, exit code: \(process.terminationStatus)]"
        }
        if output.count > 16_000 {
            return String(output.prefix(16_000)) + "\n\n… (truncated)"
        }
        return output
    }

    /// Shared approval + run path for mutating git tools.
    static func approvedRun(
        toolName: String,
        description: String,
        args: [String],
        workingDirectory: String,
        approvalDelegate: ApprovalDelegate?
    ) async throws -> String {
        if let delegate = approvalDelegate {
            let approved = await delegate.requestApproval(toolName: toolName, description: description)
            if !approved { return "Error: User rejected \(toolName.replacingOccurrences(of: "git_", with: ""))" }
        }
        return try await run(args, workingDirectory: workingDirectory)
    }
}

// MARK: - Git Status Tool

struct GitStatusTool: Tool {
    @Generable(description: "Arguments for git status")
    struct Arguments {
        @Guide(description: "Set true for short/porcelain output. Default false for readable output.")
        var short: Bool
    }

    static let name = "git_status"
    let description = "Show the working tree status — modified, staged, and untracked files."
    let workingDirectory: String

    init(workingDirectory: String) { self.workingDirectory = workingDirectory }

    func call(arguments: Arguments) async throws -> String {
        try await GitRunner.run(["status"] + (arguments.short ? ["--short"] : []), workingDirectory: workingDirectory)
    }
}

// MARK: - Git Diff Tool

struct GitDiffTool: Tool {
    @Generable(description: "Arguments for git diff")
    struct Arguments {
        @Guide(description: "Set true to show staged changes only. Default false for unstaged.")
        var staged: Bool
        @Guide(description: "Optional file path to diff a specific file. Empty = all files.")
        var filePath: String
    }

    static let name = "git_diff"
    let description = "Show git diff — unstaged or staged changes for all or a specific file."
    let workingDirectory: String

    init(workingDirectory: String) { self.workingDirectory = workingDirectory }

    func call(arguments: Arguments) async throws -> String {
        var args = ["diff"]
        if arguments.staged { args.append("--staged") }
        if !arguments.filePath.isEmpty { args.append("--"); args.append(arguments.filePath) }
        return try await GitRunner.run(args, workingDirectory: workingDirectory)
    }
}

// MARK: - Git Log Tool

struct GitLogTool: Tool {
    @Generable(description: "Arguments for git log")
    struct Arguments {
        @Guide(description: "Number of commits to show. Default 10.")
        var count: Int
        @Guide(description: "Set true for one-line format. Default false for full format.")
        var oneline: Bool
    }

    static let name = "git_log"
    let description = "Show recent git commit history."
    let workingDirectory: String

    init(workingDirectory: String) { self.workingDirectory = workingDirectory }

    func call(arguments: Arguments) async throws -> String {
        let n = arguments.count > 0 ? arguments.count : 10
        var args = ["log", "-n", String(n)]
        if arguments.oneline { args.append("--oneline") }
        return try await GitRunner.run(args, workingDirectory: workingDirectory)
    }
}

// MARK: - Git Commit Tool (with approval)

struct GitCommitTool: Tool {
    @Generable(description: "Arguments for git commit")
    struct Arguments {
        @Guide(description: "Commit message")
        var message: String
        @Guide(description: "Set true to stage all changes before committing (git add -A). Default false.")
        var stageAll: Bool
    }

    static let name = "git_commit"
    let description = "Create a git commit with a message. Optionally stage all changes first."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        let stageText = arguments.stageAll ? " (staging all with git add -A)" : ""
        if arguments.stageAll {
            let staged = try await GitRunner.approvedRun(
                toolName: "git_commit",
                description: "Commit\(stageText): \"\(arguments.message)\"",
                args: ["add", "-A"],
                workingDirectory: workingDirectory,
                approvalDelegate: approvalDelegate
            )
            if staged.hasPrefix("Error:") { return staged }
        } else if let delegate = approvalDelegate {
            let approved = await delegate.requestApproval(
                toolName: "git_commit",
                description: "Commit: \"\(arguments.message)\""
            )
            if !approved { return "Error: User rejected commit" }
        }
        return try await GitRunner.run(["commit", "-m", arguments.message], workingDirectory: workingDirectory)
    }
}

// MARK: - Git Branch Tool (with approval)

struct GitBranchTool: Tool {
    @Generable(description: "Arguments for git branch operations")
    struct Arguments {
        @Guide(description: "Action: 'list', 'create', 'checkout', or 'current'")
        var action: String
        @Guide(description: "Branch name for create or checkout. Empty for list/current.")
        var branchName: String
    }

    static let name = "git_branch"
    let description = "List, create, checkout, or show current git branch."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list":
            return try await GitRunner.run(["branch", "-a", "-v"], workingDirectory: workingDirectory)
        case "create":
            guard !arguments.branchName.isEmpty else { return "Error: branchName required for create" }
            if let delegate = approvalDelegate {
                let approved = await delegate.requestApproval(
                    toolName: "git_branch", description: "Create and checkout new branch: \(arguments.branchName)")
                if !approved { return "Error: User rejected branch creation" }
            }
            return try await GitRunner.run(["checkout", "-b", arguments.branchName], workingDirectory: workingDirectory)
        case "checkout":
            guard !arguments.branchName.isEmpty else { return "Error: branchName required for checkout" }
            if let delegate = approvalDelegate {
                let approved = await delegate.requestApproval(
                    toolName: "git_branch", description: "Checkout branch: \(arguments.branchName)")
                if !approved { return "Error: User rejected branch checkout" }
            }
            return try await GitRunner.run(["checkout", arguments.branchName], workingDirectory: workingDirectory)
        case "current":
            return try await GitRunner.run(["branch", "--show-current"], workingDirectory: workingDirectory)
        default:
            return "Error: unknown action. Use list, create, checkout, or current."
        }
    }
}

// MARK: - Git Push Tool (with approval)

struct GitPushTool: Tool {
    @Generable(description: "Arguments for git push")
    struct Arguments {
        @Guide(description: "Remote name. Default 'origin'.")
        var remote: String
        @Guide(description: "Branch name to push. Empty = current branch.")
        var branch: String
    }

    static let name = "git_push"
    let description = "Push local commits to a remote repository."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        let remoteName = arguments.remote.isEmpty ? "origin" : arguments.remote
        var args = ["push", remoteName]
        if !arguments.branch.isEmpty { args.append(arguments.branch) }
        return try await GitRunner.approvedRun(
            toolName: "git_push",
            description: "Push to \(remoteName)/\(arguments.branch)",
            args: args,
            workingDirectory: workingDirectory,
            approvalDelegate: approvalDelegate
        )
    }
}

// MARK: - Git Pull Tool (with approval)

struct GitPullTool: Tool {
    @Generable(description: "Arguments for git pull")
    struct Arguments {
        @Guide(description: "Remote name. Default 'origin'.")
        var remote: String
        @Guide(description: "Branch name to pull. Empty = current branch.")
        var branch: String
    }

    static let name = "git_pull"
    let description = "Pull changes from a remote repository."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        let remoteName = arguments.remote.isEmpty ? "origin" : arguments.remote
        var args = ["pull", remoteName]
        if !arguments.branch.isEmpty { args.append(arguments.branch) }
        return try await GitRunner.approvedRun(
            toolName: "git_pull",
            description: "Pull from \(remoteName)/\(arguments.branch)",
            args: args,
            workingDirectory: workingDirectory,
            approvalDelegate: approvalDelegate
        )
    }
}

// MARK: - Git Stash Tool (with approval)

struct GitStashTool: Tool {
    @Generable(description: "Arguments for git stash")
    struct Arguments {
        @Guide(description: "Action: 'save', 'pop', 'list', or 'drop'")
        var action: String
        @Guide(description: "Stash message for save. Stash index for drop (e.g. stash@{0}).")
        var message: String
    }

    static let name = "git_stash"
    let description = "Save, pop, list, or drop git stashes."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list":
            return try await GitRunner.run(["stash", "list"], workingDirectory: workingDirectory)
        case "save":
            if let delegate = approvalDelegate {
                let approved = await delegate.requestApproval(
                    toolName: "git_stash", description: "Stash changes\(arguments.message.isEmpty ? "" : ": \(arguments.message)")")
                if !approved { return "Error: User rejected stash" }
            }
            var args = ["stash", "push"]
            if !arguments.message.isEmpty { args.append("-m"); args.append(arguments.message) }
            return try await GitRunner.run(args, workingDirectory: workingDirectory)
        case "pop":
            if let delegate = approvalDelegate {
                let approved = await delegate.requestApproval(
                    toolName: "git_stash", description: "Pop most recent stash")
                if !approved { return "Error: User rejected stash pop" }
            }
            return try await GitRunner.run(["stash", "pop"], workingDirectory: workingDirectory)
        case "drop":
            if let delegate = approvalDelegate {
                let approved = await delegate.requestApproval(
                    toolName: "git_stash", description: "Drop stash: \(arguments.message.isEmpty ? "stash@{0}" : arguments.message)")
                if !approved { return "Error: User rejected stash drop" }
            }
            let target = arguments.message.isEmpty ? "stash@{0}" : arguments.message
            return try await GitRunner.run(["stash", "drop", target], workingDirectory: workingDirectory)
        default:
            return "Error: unknown action. Use save, pop, list, or drop."
        }
    }
}

// MARK: - Git Restore Tool (with approval)

struct GitRestoreTool: Tool {
    @Generable(description: "Arguments for git restore")
    struct Arguments {
        @Guide(description: "File path to restore. Empty = all files.")
        var path: String
        @Guide(description: "Set true to restore staged changes (unstage). Default false.")
        var staged: Bool
    }

    static let name = "git_restore"
    let description = "Restore working tree files to their last committed state."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.path.isEmpty ? "all files" : arguments.path
        var args = ["restore"]
        if arguments.staged { args.append("--staged") }
        if arguments.path.isEmpty { args.append(".") } else { args.append(arguments.path) }
        return try await GitRunner.approvedRun(
            toolName: "git_restore",
            description: "Restore \(target) to last committed state",
            args: args,
            workingDirectory: workingDirectory,
            approvalDelegate: approvalDelegate
        )
    }
}

// MARK: - Git Add Tool (with approval)

struct GitAddTool: Tool {
    @Generable(description: "Arguments for git add")
    struct Arguments {
        @Guide(description: "File path(s) to stage. Use '.' for all files. Empty defaults to '.'.")
        var path: String
    }

    static let name = "git_add"
    let description = "Stage file(s) for commit. Use '.' or empty for all changes."
    let workingDirectory: String
    let approvalDelegate: ApprovalDelegate?

    init(workingDirectory: String, approvalDelegate: ApprovalDelegate? = nil) {
        self.workingDirectory = workingDirectory
        self.approvalDelegate = approvalDelegate
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.path.isEmpty ? "all files" : arguments.path
        let path = arguments.path.isEmpty ? "." : arguments.path
        return try await GitRunner.approvedRun(
            toolName: "git_add",
            description: "Stage \(target)",
            args: ["add", path],
            workingDirectory: workingDirectory,
            approvalDelegate: approvalDelegate
        )
    }
}

// MARK: - Git Show Tool

struct GitShowTool: Tool {
    @Generable(description: "Arguments for git show")
    struct Arguments {
        @Guide(description: "Commit hash, ref, or HEAD~N to show. Default HEAD.")
        var ref: String
    }

    static let name = "git_show"
    let description = "Show the content of a specific commit — diff, message, and metadata."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        let ref = arguments.ref.isEmpty ? "HEAD" : arguments.ref
        return try await GitRunner.run(["show", "--stat", ref], workingDirectory: workingDirectory)
    }
}

// MARK: - Git Remote Tool

struct GitRemoteTool: Tool {
    @Generable(description: "Arguments for git remote")
    struct Arguments {
        @Guide(description: "Action: 'list' or 'add'. Default 'list'.")
        var action: String
        @Guide(description: "Remote name for add. Empty for list.")
        var name: String
        @Guide(description: "Remote URL for add. Empty for list.")
        var url: String
    }

    static let name = "git_remote"
    let description = "List or add git remotes."
    let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list", "":
            return try await GitRunner.run(["remote", "-v"], workingDirectory: workingDirectory)
        case "add":
            guard !arguments.name.isEmpty, !arguments.url.isEmpty else {
                return "Error: name and url required for add"
            }
            return try await GitRunner.run(["remote", "add", arguments.name, arguments.url], workingDirectory: workingDirectory)
        default:
            return "Error: unknown action. Use 'list' or 'add'."
        }
    }
}
