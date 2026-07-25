import SwiftUI
import Charts

struct InspectorView: View {
    let store: ConversationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let convo = store.selectedConversation {
                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conversation").font(.headline)
                            LabeledContent("Title") { Text(convo.title).lineLimit(1) }
                            LabeledContent("Created") { Text(convo.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                            LabeledContent("Updated") { Text(convo.updatedAt.formatted(date: .abbreviated, time: .shortened)) }
                            LabeledContent("Messages") { Text("\(convo.messages.count)") }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Project").font(.headline)
                            if let path = convo.projectPath {
                                LabeledContent("Path") { Text(path).lineLimit(2).font(.caption) }
                            } else {
                                Text("No project").foregroundStyle(.secondary)
                            }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model").font(.headline)
                            LabeledContent("Model") { Text(convo.modelChoice.rawValue) }
                            LabeledContent("Mode") {
                                Label(convo.workMode.rawValue, systemImage: convo.workMode.icon)
                            }
                            LabeledContent("Available") {
                                Text(store.ai.isAvailable ? "Yes" : "No")
                                    .foregroundStyle(store.ai.isAvailable ? .green : .red)
                            }
                            if !store.ai.modelCapabilities.isEmpty {
                                LabeledContent("Capabilities") {
                                    Text(store.ai.modelCapabilities.joined(separator: ", "))
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tokens").font(.headline)
                            LabeledContent("Input") { Text("\(store.ai.inputTokenCount)") }
                            LabeledContent("Output") { Text("\(store.ai.outputTokenCount)") }
                            LabeledContent("Context") { Text("\(store.ai.contextWindowUsed)") }

                            let tokenData: [(String, Int)] = [
                                ("Input", store.ai.inputTokenCount),
                                ("Output", store.ai.outputTokenCount),
                                ("Context", store.ai.contextWindowUsed)
                            ]
                            Chart(tokenData, id: \.0) { item in
                                BarMark(
                                    x: .value("Type", item.0),
                                    y: .value("Tokens", item.1)
                                )
                                .foregroundStyle(by: .value("Type", item.0))
                            }
                            .frame(height: 120)
                            .chartXAxis { AxisMarks(values: .automatic) }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("File Changes").font(.headline)
                            if convo.fileChanges.isEmpty {
                                Text("None").foregroundStyle(.secondary)
                            } else {
                                ForEach(convo.fileChanges) { change in
                                    HStack {
                                        Image(systemName: changeIcon(change.changeType))
                                            .foregroundStyle(changeColor(change.changeType))
                                        Text((change.path as NSString).lastPathComponent)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tools").font(.headline)
                            LabeledContent("Built-in") { Text("19") }
                            LabeledContent("MCP") { Text("\(store.mcpClient.discoveredTools.count)") }
                            LabeledContent("Plugin") { Text("\(store.pluginManager.pluginTools.count)") }
                            LabeledContent("Skills") { Text("\(store.skillsService.skills.count)") }
                        }
                    }
                } else {
                    Text("No conversation selected")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreAIPanel(cornerRadius: 10)
    }

    private func changeIcon(_ type: FileChange.ChangeType) -> String {
        switch type {
        case .created: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        }
    }

    private func changeColor(_ type: FileChange.ChangeType) -> Color {
        switch type {
        case .created: return .green
        case .modified: return .orange
        case .deleted: return .red
        }
    }
}
