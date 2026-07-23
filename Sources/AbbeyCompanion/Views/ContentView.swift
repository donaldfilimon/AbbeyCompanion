import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case users = "Users"
    case channels = "Channels"
    case messages = "Messages"
    case activity = "Activity"
    case personas = "Personas"
    case equity = "Equity Research"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .users: return "person.2"
        case .channels: return "number"
        case .messages: return "bubble.left.and.bubble.right"
        case .activity: return "list.bullet.rectangle"
        case .personas: return "sparkles"
        case .equity: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct ContentView: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var selection: SidebarSection? = .dashboard
    @State private var pendingConfirmation: ConfirmationGate.PendingRequest?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases.filter { section in
                    section != .equity || engine.config.equityModuleEnabled
                }) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
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
    }

    private func presentPendingConfirmation() async {
        let queue = await engine.confirmationGate.queue
        pendingConfirmation = queue.first
    }
}
