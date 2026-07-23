import Foundation

/// Human-in-the-loop gate for purge/kick/ban. Nothing in this app executes a
/// destructive action directly — every call site routes through `request(_:target:guild:)`,
/// which either resolves immediately (if `AppConfig.confirmationRequiredForDestructiveActions`
/// is false, e.g. in a scripted test context) or suspends until a UI confirmation sheet
/// resolves the pending request.
///
/// This mirrors the same-named actor from the prior native macOS SwiftData architecture
/// (2026-06-29 session) — see /areas/abbey-bot.md.
package actor ConfirmationGate {
    struct PendingRequest: Identifiable, Sendable {
        let id: UUID
        let kind: DestructiveAction
        let targetUserId: String
        let guildId: String
        let reason: String
        let requestedAt: Date
    }

    private var pending: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private(set) var queue: [PendingRequest] = []

    private let requireConfirmation: @Sendable () -> Bool
    private let eventBus: EventBus

    init(eventBus: EventBus, requireConfirmation: @escaping @Sendable () -> Bool) {
        self.eventBus = eventBus
        self.requireConfirmation = requireConfirmation
    }

    /// Suspends until the pending request is confirmed or cancelled from the UI.
    /// Returns `true` if the caller should proceed with the destructive action.
    func request(kind: DestructiveAction, targetUserId: String, guildId: String, reason: String) async -> Bool {
        await eventBus.publish(.destructiveActionRequested(kind: kind, targetUserId: targetUserId, guildId: guildId))

        guard requireConfirmation() else { return true }

        let item = PendingRequest(
            id: UUID(),
            kind: kind,
            targetUserId: targetUserId,
            guildId: guildId,
            reason: reason,
            requestedAt: .now
        )
        queue.append(item)

        return await withCheckedContinuation { continuation in
            pending[item.id] = continuation
        }
    }

    /// Called by the confirmation sheet when the user taps Confirm.
    func confirm(_ id: UUID) async {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let item = queue.first(where: { $0.id == id }) {
            queue.removeAll { $0.id == id }
            await eventBus.publish(.destructiveActionConfirmed(kind: item.kind, targetUserId: item.targetUserId, guildId: item.guildId))
        }
        continuation.resume(returning: true)
    }

    /// Called by the confirmation sheet when the user taps Cancel, or dismisses it.
    func cancel(_ id: UUID) async {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let item = queue.first(where: { $0.id == id }) {
            queue.removeAll { $0.id == id }
            await eventBus.publish(.destructiveActionCancelled(kind: item.kind, targetUserId: item.targetUserId))
        }
        continuation.resume(returning: false)
    }
}
