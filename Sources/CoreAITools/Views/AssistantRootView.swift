import SwiftUI
import UniformTypeIdentifiers

/// Root navigation view for CoreAI Assistant. Embeds a sidebar–detail split with
/// a conversation list, an inspector, and drag-and-drop folder support. Creates
/// and owns the `ConversationStore` that drives the entire assistant UI.
package struct AssistantRootView: View {
    @State private var store: ConversationStore
    @State private var showProjectPicker = false
    @State private var showInspector = false
    @State private var persistenceWarning: String?

    package init(bootstrap: ConversationStoreBootstrap = .init()) {
        _store = State(initialValue: ConversationStore(bootstrap: bootstrap))
    }

    package var body: some View {
        NavigationSplitView {
            SidebarView(store: store, showProjectPicker: $showProjectPicker)
        } detail: {
            if store.selectedConversation != nil {
                ChatView(store: store)
            } else {
                WelcomeView(
                    onNewConversation: { showProjectPicker = true },
                    onOpenProject: { showProjectPicker = true }
                )
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(store: store)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .frame(minWidth: 800, minHeight: 550)
        .containerBackground(AppearanceSettings.shared.surfaceStyle, for: .window)
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(store: store, isPresented: $showProjectPicker)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            store.refreshModelStatus()
            persistenceWarning = ConversationPersistence.lastError
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
            }
        }
        .overlay(alignment: .top) {
            if let warning = persistenceWarning {
                PersistenceWarningBanner(message: warning) {
                    withAnimation { persistenceWarning = nil }
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: persistenceWarning)
    }

    /// Accepts a dropped folder URL and opens a new conversation rooted at that directory.
    @MainActor
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { item, _ in
                    guard let url = item else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                    Task { @MainActor in
                        store.newConversation(projectPath: url.path)
                    }
                }
                return true
            }
        }
        return false
    }
}

/// Inline banner shown at the top of the window when a SwiftData persistence error
/// was encountered during the previous session. Dismissible by the user.
package struct PersistenceWarningBanner: View {
    let message: String
    let dismiss: () -> Void

    package var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.orange.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal, 12)
    }
}

/// Modal sheet for creating a new conversation. Lets the user choose a model
/// variant and pick a project folder via the system folder picker.
package struct ProjectPickerSheet: View {
    let store: ConversationStore
    @Binding var isPresented: Bool
    @State private var selectedModel: Conversation.ModelChoice = .systemDefault

    init(store: ConversationStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
    }

    package var body: some View {
        VStack(spacing: 16) {
            Text("New Conversation").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Model").font(.subheadline).foregroundStyle(.secondary)
                Picker("Model", selection: $selectedModel) {
                    ForEach(Conversation.ModelChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Select a project directory for the AI to work in.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder…") {
                    if let path = FileService.openFolderPanel() {
                        store.newConversation(projectPath: path, modelChoice: selectedModel)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
