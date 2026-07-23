import Foundation
import Observation

@MainActor
@Observable
final class ApprovalGate {
    /// How approval prompts are presented. `.gui` suspends for the
    /// AppKit banner; `.terminal` reads a `y/N` answer from stdin so the
    /// CLI / TUI / batch runners don't deadlock waiting on a UI that
    /// isn't there.
    enum InteractionMode: Sendable { case gui, terminal }
    var interactionMode: InteractionMode = .gui

    var pendingRequest: PendingApproval?
    var isApprovalEnabled: Bool = true

    final class PendingApproval: Identifiable {
        let id: UUID
        let toolName: String
        let description: String
        private var continuation: CheckedContinuation<Bool, Never>?
        private var isResolved = false

        init(id: UUID, toolName: String, description: String, continuation: CheckedContinuation<Bool, Never>) {
            self.id = id
            self.toolName = toolName
            self.description = description
            self.continuation = continuation
        }

        func resume(returning value: Bool) {
            guard !isResolved else { return }
            isResolved = true
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    func requestApproval(toolName: String, description: String) async -> Bool {
        guard isApprovalEnabled else { return true }

        if interactionMode == .terminal {
            return await withCheckedContinuation { continuation in
                // Read from a detached task so we never block the main actor
                // (which the GUI Resume path relies on) and never race the
                // REPL's own `readLine` (only active between prompts).
                Task.detached {
                    let answer = readTerminalAnswer(toolName: toolName, description: description)
                    continuation.resume(returning: answer)
                }
            }
        }

        return await withCheckedContinuation { continuation in
            // A new request supersedes any existing one. Reject the old
            // request (never auto-approve a request the user never saw) so a
            // not-yet-shown destructive action is cancelled, not silently allowed.
            if let existing = pendingRequest {
                existing.resume(returning: false)
            }
            pendingRequest = PendingApproval(
                id: UUID(),
                toolName: toolName,
                description: description,
                continuation: continuation
            )
        }
    }

    func approve() {
        guard let pending = pendingRequest else { return }
        pending.resume(returning: true)
        pendingRequest = nil
    }

    func reject() {
        guard let pending = pendingRequest else { return }
        pending.resume(returning: false)
        pendingRequest = nil
    }

    /// Cancel any pending approval — reject it so a destructive action is
    /// never silently approved. Cancelling a stream must not approve a
    /// pending `write_file` / `git_push`.
    func cancelAll() {
        if let pending = pendingRequest {
            pending.resume(returning: false)
            pendingRequest = nil
        }
    }
}

/// Free (non-isolated) helper so a detached task can read the `y/N`
/// answer from stdin without crossing the `ApprovalGate` main-actor
/// boundary. Returns `false` (reject) when there is no TTY / input
/// is piped, matching "non-interactive rejects".
private func readTerminalAnswer(toolName: String, description: String) -> Bool {
    let prompt = "\n🔒 Approve tool call `\(toolName)`?\n\(description)\n[y/N]: "
    FileHandle.standardOutput.write(Data(prompt.utf8))
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return false
    }
    return line == "y" || line == "yes"
}

// MARK: - Approval Delegate (Sendable, used by tools)

actor ApprovalDelegate: Sendable {
    private let gate: ApprovalGate

    init(gate: ApprovalGate) {
        self.gate = gate
    }

    func requestApproval(toolName: String, description: String) async -> Bool {
        await gate.requestApproval(toolName: toolName, description: description)
    }
}
