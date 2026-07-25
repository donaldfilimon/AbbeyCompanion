import SwiftUI

package enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case users = "Users"
    case channels = "Channels"
    case messages = "Messages"
    case activity = "Activity"
    case personas = "Personas"
    case equity = "Equity Research"
    case statistics = "Statistics"
    case aiAssistant = "AI Assistant"

    package var id: String { rawValue }

    package var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .users: return "person.2"
        case .channels: return "number"
        case .messages: return "bubble.left.and.bubble.right"
        case .activity: return "list.bullet.rectangle"
        case .personas: return "sparkles"
        case .equity: return "chart.line.uptrend.xyaxis"
        case .statistics: return "chart.bar.xaxis.ascending"
        case .aiAssistant: return "cpu"
        }
    }

    package var shortcut: KeyEquivalent {
        switch self {
        case .dashboard: return "1"
        case .users: return "2"
        case .channels: return "3"
        case .messages: return "4"
        case .activity: return "5"
        case .personas: return "6"
        case .equity: return "7"
        case .statistics: return "8"
        case .aiAssistant: return "9"
        }
    }
}

/// Root companion shell. AI Assistant slot is injected by the app target so kit stays free of CoreAITools.
package struct AbbeyRootView<AIAssistant: View>: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var selection: SidebarSection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingConfirmation: ConfirmationGate.PendingRequest?
    @State private var showGlobalSearch = false
    @AppStorage("abbey.sidebarSelection") private var savedSelection = "dashboard"

    private let aiAssistant: AIAssistant

    package init(
        initialSelection: SidebarSection = .dashboard,
        @ViewBuilder aiAssistant: () -> AIAssistant
    ) {
        _selection = State(initialValue: initialSelection)
        self.aiAssistant = aiAssistant()
    }

    package var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases.filter { section in
                    section != .equity || engine.config.equityModuleEnabled
                }) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                        .keyboardShortcut(section.shortcut, modifiers: [.command])
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .navigationTitle("Abbey")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(engine.config.operatingMode.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                        if engine.config.operatingMode == .mirror {
                            Text("local schema")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(engine.config.inferenceMode.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if engine.metrics.storeDegraded {
                        Text("in-memory store")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            NavigationStack {
                switch selection {
                case .dashboard, .none:
                    DashboardView()
                case .users:
                    UsersView()
                case .channels:
                    ChannelContextsView()
                case .messages:
                    MessagesView()
                case .activity:
                    ActivityView()
                case .personas:
                    PersonaSwitcherView()
                case .equity:
                    EquityResearchView()
                case .statistics:
                    StatisticsView()
                case .aiAssistant:
                    aiAssistant
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, newValue in
            if let section = newValue {
                savedSelection = section.rawValue
            }
        }
        .onChange(of: engine.confirmationTick) {
            Task { await presentPendingConfirmation() }
        }
        .onChange(of: engine.config.equityModuleEnabled) {
            if !engine.config.equityModuleEnabled, selection == .equity {
                selection = .dashboard
            }
        }
        .sheet(item: $pendingConfirmation) { request in
            ConfirmationSheetView(request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .abbeyExportRequested)) { _ in
            handleExport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abbeyImportRequested)) { _ in
            handleImport()
        }
        .inspector(isPresented: $showGlobalSearch) {
            GlobalSearchView(engine: engine, isPresented: $showGlobalSearch)
        }
    }

    private func presentPendingConfirmation() async {
        let queue = await engine.confirmationGate.queue
        pendingConfirmation = queue.first
    }

    private func handleExport() {
        guard let data = try? engine.exportJSON() else { return }
        _ = DocumentIO.runJSONExport(data: data)
    }

    private func handleImport() {
        guard let data = DocumentIO.runJSONImport() else { return }
        _ = try? engine.importJSON(data)
    }
}

package struct AbbeyAIAssistantPlaceholder: View {
    package init() {}
    package var body: some View {
        Text("AI Assistant is hosted by the app shell.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AbbeyRootView where AIAssistant == AbbeyAIAssistantPlaceholder {
    /// Preview / kit-only convenience without an AI assistant host.
    package init(initialSelection: SidebarSection = .dashboard) {
        self.init(initialSelection: initialSelection) {
            AbbeyAIAssistantPlaceholder()
        }
    }
}

#Preview("Abbey Root") {
    let engine = AbbeyStore.makePreviewEngine()
    AbbeyRootView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
