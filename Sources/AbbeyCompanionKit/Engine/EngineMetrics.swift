import Foundation

/// In-memory counters for the Dashboard view. Deliberately not persisted — these reset
/// each launch, since they describe "this session," not historical fact (historical
/// fact lives in the SwiftData models and is queried directly by the views that need it).
@Observable
package final class EngineMetrics: @unchecked Sendable {
    private(set) var messagesIngestedThisSession: Int = 0
    private(set) var reputationEventsThisSession: Int = 0
    private(set) var inferenceCallsByMode: [InferenceMode: Int] = [:]
    private(set) var inferenceFailuresByMode: [InferenceMode: Int] = [:]
    private(set) var destructiveActionsConfirmed: Int = 0
    private(set) var destructiveActionsCancelled: Int = 0
    private(set) var storeDegraded: Bool = false
    private(set) var lastConsolidationAt: Date?

    package func recordMessageIngested() {
        messagesIngestedThisSession += 1
    }

    package func recordReputationEvent() {
        reputationEventsThisSession += 1
    }

    package func recordInferenceCall(mode: InferenceMode, succeeded: Bool) {
        inferenceCallsByMode[mode, default: 0] += 1
        if !succeeded {
            inferenceFailuresByMode[mode, default: 0] += 1
        }
    }

    package func recordDestructiveAction(confirmed: Bool) {
        if confirmed {
            destructiveActionsConfirmed += 1
        } else {
            destructiveActionsCancelled += 1
        }
    }

    package func recordConsolidation() {
        lastConsolidationAt = .now
    }

    package func markStoreDegraded() {
        storeDegraded = true
    }
}
