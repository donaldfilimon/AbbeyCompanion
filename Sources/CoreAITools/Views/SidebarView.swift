import SwiftUI

struct SidebarView: View {
    let store: ConversationStore
    @Binding var showProjectPicker: Bool
    @State private var selectedTab: SidebarTab = .conversations

    init(store: ConversationStore, showProjectPicker: Binding<Bool>) {
        self.store = store
        self._showProjectPicker = showProjectPicker
    }

    enum SidebarTab: String, CaseIterable, Identifiable {
        case conversations = "Chats"
        case files = "Files"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            switch selectedTab {
            case .conversations:
                conversationList
            case .files:
                fileTreeList
            }
        }
        .navigationTitle("CoreAI")
        .background(
            AppearanceSettings.shared.sidebarStyle == .glass
                ? AppearanceSettings.shared.surfaceStyle
                : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .toolbar {
            ToolbarItem {
                Button {
                    showProjectPicker = true
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { store.selectedConversationID },
                set: { newId in if let id = newId { store.select(id) } }
            )) {
                Section {
                    Button {
                        showProjectPicker = true
                    } label: {
                        Label("New Conversation", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                }
                Section("\(store.filteredConversations.count) conversation\(store.filteredConversations.count == 1 ? "" : "s")") {
                    ForEach(store.filteredConversations) { convo in
                        SidebarRow(conversation: convo, store: store)
                    }
                }
            }
            .searchable(text: Binding(get: { store.searchQuery }, set: { store.searchQuery = $0 }), prompt: "Search conversations…")
        }
    }

    // MARK: - File Tree

    private var fileTreeList: some View {
        VStack(spacing: 0) {
            if let path = store.selectedConversation?.projectPath {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.headline)
                    Spacer()
                    if store.fileWatcher.lastChangeTime != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)

                List {
                    if store.fileTree.isLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(store.fileTree.rootEntries) { entry in
                            FileTreeRow(entry: entry, level: 0)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Project Open",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a new conversation and select a project folder.")
                )
            }

            // File changes summary
            if !store.fileChanges.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session Changes")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.fileChanges.count)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(store.fileChanges) { change in
                        HStack(spacing: 4) {
                            Image(systemName: changeIcon(change.changeType))
                                .font(.caption2)
                                .foregroundStyle(changeColor(change.changeType))
                            Text((change.path as NSString).lastPathComponent)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .coreAIGlass()
            }
        }
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

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let conversation: Conversation
    let store: ConversationStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let path = conversation.projectPath {
                        Text((path as NSString).lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !conversation.fileChanges.isEmpty {
                        Text("\(conversation.fileChanges.count) changes")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    // Work mode badge
                    Image(systemName: conversation.workMode.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                store.delete(conversation.id)
            }
        }
    }
}

// MARK: - File Tree Row

private struct FileTreeRow: View {
    let entry: FileTreeService.FileEntry
    let level: Int
    @State private var isExpanded: Bool

    init(entry: FileTreeService.FileEntry, level: Int) {
        self.entry = entry
        self.level = level
        self._isExpanded = State(initialValue: entry.isExpanded)
    }

    var body: some View {
        HStack(spacing: 4) {
            if entry.isDirectory {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: isExpanded ? "folder.open" : "folder")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: fileIcon)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }

            Text(entry.name)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(level) * 12)

        if isExpanded, let children = entry.children {
            ForEach(children) { child in
                FileTreeRow(entry: child, level: level + 1)
            }
        }
    }

    private var fileIcon: String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json": return "doc.text.below.ecg"
        case "md": return "doc.richtext"
        case "py": return "doc.text"
        case "sh": return "terminal"
        case "html": return "globe"
        case "css": return "paintbrush"
        default: return "doc"
        }
    }
}
