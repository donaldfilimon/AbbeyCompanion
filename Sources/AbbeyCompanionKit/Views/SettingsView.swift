import SwiftUI

package enum AppAccentColor: String, CaseIterable {
    case blue, purple, green, orange, pink, teal, indigo, mint

    package var label: String { rawValue.capitalized }
    package var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .teal: return .teal
        case .indigo: return .indigo
        case .mint: return .mint
        }
    }
}

package enum AppFontSize: String, CaseIterable {
    case small, medium, large

    package var label: String { rawValue.capitalized }
    package var scale: Double {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }
}

package struct SettingsView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Bindable private var config = AppConfig.shared
    @State private var remoteProbeResult = ""
    @State private var isProbing = false
    @State private var onDeviceStatus = OnDeviceModelProbe.status()
    @AppStorage("abbey.accentColor") private var accentColor = AppAccentColor.blue
    @AppStorage("abbey.fontSize") private var fontSize = AppFontSize.medium

    package init() {}

    package var body: some View {
        Form {
            Section("Operating mode") {
                Picker("ABBEY_OPERATING_MODE", selection: $config.operatingMode) {
                    ForEach(OperatingMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                Text(config.operatingMode == .standalone
                     ? "Everything runs in-process against the local SwiftData store."
                     : "Same conceptual schema as the Vapor/Fluent bot; local SwiftData only — no Postgres sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Inference") {
                Picker("ABBEY_INFERENCE_MODE", selection: $config.inferenceMode) {
                    ForEach(InferenceMode.allCases) { mode in
                        Text(label(for: mode)).tag(mode)
                    }
                }
                if config.inferenceMode == .remoteCompatible {
                    TextField("ABBEY_REMOTE_ENDPOINT", text: $config.remoteEndpoint, prompt: Text("https://host/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)
                    SecureField("ABBEY_REMOTE_API_KEY (optional)", text: $config.remoteAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("ABBEY_REMOTE_MODEL", text: $config.remoteModel)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await probeRemote() }
                    } label: {
                        if isProbing { ProgressView().controlSize(.small) } else { Text("Probe remote endpoint") }
                    }
                    .disabled(config.remoteEndpoint.isEmpty || isProbing)
                    if !remoteProbeResult.isEmpty {
                        Text(remoteProbeResult)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if config.inferenceMode == .onDevice {
                    LabeledContent("Foundation Models") {
                        Text(onDeviceStatus.label)
                    }
                    Button("Refresh on-device status") {
                        onDeviceStatus = OnDeviceModelProbe.status()
                    }
                    Text("Falls back to the deterministic floor if Foundation Models is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Classification") {
                Toggle("ABBEY_USE_STRICT_INTENT", isOn: $config.useStrictIntentClassification)
                Text("When on, tiny/non-letter input becomes `.unknown` instead of `.smallTalk` (classifyStrict).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory consolidation") {
                Toggle("ABBEY_ABSTRACTIVE_CONSOLIDATION", isOn: $config.useAbstractiveConsolidation)
                Text("When on, channel summaries use the active inference provider (falls back to extractive transcript). Off = most-recent-N extractive only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Consolidate all channels now") {
                    Task { await engine.scheduler.consolidateAllChannels() }
                }
            }

            Section("Timing") {
                LabeledContent("ABBEY_REPLY_COOLDOWN_SECONDS") {
                    Stepper(value: $config.replyCooldownSeconds, in: 0...120, step: 1) {
                        Text("\(Int(config.replyCooldownSeconds)) s")
                    }
                }
                LabeledContent("ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN") {
                    Stepper(value: $config.memoryConsolidationIntervalMinutes, in: 1...240, step: 1) {
                        Text("\(Int(config.memoryConsolidationIntervalMinutes)) min")
                    }
                }
                Button("Restart consolidation loop with current interval") {
                    Task { await engine.scheduler.start() }
                }
            }

            Section("Reputation") {
                LabeledContent("ABBEY_REPUTATION_DECAY") {
                    Slider(value: $config.reputationDecay, in: 0.5...0.99, step: 0.01) {
                        Text("Decay")
                    }
                }
                Text("EMA weight on existing score. Current: \(String(format: "%.2f", config.reputationDecay))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                Toggle("ABBEY_CONFIRMATION_REQUIRED", isOn: $config.confirmationRequiredForDestructiveActions)
            }

            Section("Modules") {
                Toggle("ABBEY_EQUITY_MODULE_ENABLED", isOn: $config.equityModuleEnabled)
            }

            Section("Appearance") {
                LabeledContent("Accent color") {
                    Picker("", selection: $accentColor) {
                        ForEach(AppAccentColor.allCases, id: \.rawValue) { color in
                            HStack {
                                Circle().fill(color.swiftUIColor).frame(width: 12, height: 12)
                                Text(color.label)
                            }
                            .tag(color)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("Font size") {
                    Picker("", selection: $fontSize) {
                        Text("Small").tag(AppFontSize.small)
                        Text("Medium").tag(AppFontSize.medium)
                        Text("Large").tag(AppFontSize.large)
                    }
                    .labelsHidden()
                }
            }

            Section("DQN") {
                LabeledContent("Steps") { Text("\(engine.dqnStepCount)") }
                LabeledContent("Replay buffer") { Text("\(engine.dqnExperienceCount)") }
                LabeledContent("Gamma (discount)") {
                    Slider(value: $config.dqnGamma, in: 0.5...0.999, step: 0.01) {
                        Text("Gamma")
                    }
                    .onChange(of: config.dqnGamma) { _, _ in Task { await engine.syncDQNConfig() } }
                }
                Text("Current: \(String(format: "%.3f", config.dqnGamma))")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Epsilon (exploration)") {
                    Slider(value: $config.dqnEpsilon, in: 0.0...0.5, step: 0.01) {
                        Text("Epsilon")
                    }
                    .onChange(of: config.dqnEpsilon) { _, _ in Task { await engine.syncDQNConfig() } }
                }
                Text("Current: \(String(format: "%.2f", config.dqnEpsilon))")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Learning rate") {
                    Slider(value: $config.dqnLearningRate, in: 0.0001...0.1, step: 0.0001) {
                        Text("LR")
                    }
                    .onChange(of: config.dqnLearningRate) { _, _ in Task { await engine.syncDQNConfig() } }
                }
                Text("Current: \(String(format: "%.4f", config.dqnLearningRate))")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Batch size") {
                    Stepper(value: $config.dqnBatchSize, in: 1...128, step: 1) {
                        Text("\(config.dqnBatchSize)")
                    }
                    .onChange(of: config.dqnBatchSize) { _, _ in Task { await engine.syncDQNConfig() } }
                }
                Text("Weights auto-save under Application Support after each learn/reward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset DQN weights…", role: .destructive) {
                    Task { await engine.resetDQNWeights() }
                }
            }

            Section("Danger zone") {
                if let consolidated = engine.metrics.lastConsolidationAt {
                    LabeledContent("Last consolidation") {
                        Text(consolidated, style: .relative)
                    }
                }
                Button("Reset local store…", role: .destructive) {
                    NotificationCenter.default.post(name: .abbeyResetStoreRequested, object: nil)
                }
                Text("Deletes SwiftData rows only. ABBEY_* Settings persist in UserDefaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .navigationTitle("Settings")
    }

    private func label(for mode: InferenceMode) -> String {
        switch mode {
        case .deterministicFloor: return "Deterministic floor (rule-based, no model)"
        case .onDevice: return "On-device (Foundation Models)"
        case .remoteCompatible: return "Remote (OpenAI-compatible endpoint)"
        }
    }

    private func probeRemote() async {
        isProbing = true
        defer { isProbing = false }
        let result = await engine.inferenceRouter.probeRemote()
        switch result {
        case .success(let text):
            remoteProbeResult = "ok: \(text)"
        case .failure(let error):
            remoteProbeResult = "fail: \(error.localizedDescription)"
        }
    }
}
