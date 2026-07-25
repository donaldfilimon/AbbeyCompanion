import SwiftUI
import SwiftData

struct UsersView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \UserMemory.reputation, order: .reverse) private var allUsers: [UserMemory]
    @State private var selectedUserID: PersistentIdentifier?
    @State private var search = ""

    private var displayedUsers: [UserMemory] {
        StoreFilters.filterUsers(allUsers, search: search)
    }

    private var selectedUser: UserMemory? {
        if let id = selectedUserID {
            return displayedUsers.first { $0.persistentModelID == id }
                ?? allUsers.first { $0.persistentModelID == id }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if displayedUsers.isEmpty {
                    ContentUnavailableView(
                        allUsers.isEmpty ? "No users yet" : "No matches",
                        systemImage: "person.2",
                        description: Text(emptyDescription)
                    )
                } else {
                    List(displayedUsers, selection: $selectedUserID) { user in
                        VStack(alignment: .leading) {
                            Text(user.discordUserId).font(.headline)
                            Text(
                                "guild: \(user.guildId) · rep: \(String(format: "%.2f", user.reputation)) · \(user.interactionCount) interactions · \(user.reputationEvents.count) events"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(user.persistentModelID)
                    }
                    .frame(minWidth: 240, idealWidth: 280)
                }
            }

            Divider()

            Group {
                if let user = selectedUser {
                    UserDetailView(user: user)
                        .id(user.persistentModelID)
                } else {
                    ContentUnavailableView("Select a user", systemImage: "person")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Users")
        .searchable(text: $search, prompt: "User, guild, or fact")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await engine.socialBrain.warmCache() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh reputation cache")
            }
        }
        .onChange(of: search) {
            pruneSelectionIfNeeded()
        }
        .onChange(of: displayedUsers.count) {
            pruneSelectionIfNeeded()
        }
    }

    private var emptyDescription: String {
        if allUsers.isEmpty {
            return "Ingest a message on the Dashboard to create UserMemory rows via SocialBrain."
        }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Try a broader search."
        }
        return "No matches for \"\(trimmed)\"."
    }

    private func pruneSelectionIfNeeded() {
        guard let id = selectedUserID else { return }
        let stillVisible = displayedUsers.contains { $0.persistentModelID == id }
        if !stillVisible {
            selectedUserID = nil
        }
    }
}

private struct UserDetailView: View {
    @Environment(AbbeyEngine.self) private var engine
    let user: UserMemory
    @State private var reason = ""
    @State private var newFact = ""

    private var events: [ReputationEvent] {
        StoreFilters.sortedReputationEvents(for: user)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(user.discordUserId).font(.largeTitle.bold())
                Text("Guild: \(user.guildId)")
                Text("Reputation: \(String(format: "%.3f", user.reputation))")
                Text("Interactions: \(user.interactionCount)")

                GroupBox("Facts") {
                    VStack(alignment: .leading, spacing: 8) {
                        if user.facts.isEmpty {
                            Text("No facts yet — add one below or ingest “remember …”")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(user.facts, id: \.self) { fact in
                                HStack {
                                    Text("• \(fact)")
                                    Spacer()
                                    Button(role: .destructive) {
                                        engine.removeFact(
                                            userId: user.discordUserId,
                                            guildId: user.guildId,
                                            fact: fact
                                        )
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        HStack {
                            TextField("Add fact", text: $newFact)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let fact = newFact
                                newFact = ""
                                Task {
                                    await engine.addFact(
                                        userId: user.discordUserId,
                                        guildId: user.guildId,
                                        fact: fact
                                    )
                                }
                            }
                            .disabled(newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Reputation history") {
                    if events.isEmpty {
                        Text("No events yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(events.prefix(25)) { event in
                            HStack {
                                Text(event.reason)
                                Spacer()
                                Text(String(format: "%+.3f", event.delta))
                                    .foregroundStyle(event.delta >= 0 ? .green : .red)
                                Text(event.createdAt, style: .relative)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                GroupBox("Moderation") {
                    HStack {
                        TextField("Reason", text: $reason)
                            .textFieldStyle(.roundedBorder)
                        Button("Purge") {
                            requestAction(.purge)
                        }
                        Button("Kick", role: .destructive) {
                            requestAction(.kick)
                        }
                        Button("Ban", role: .destructive) {
                            requestAction(.ban)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func requestAction(_ kind: DestructiveAction) {
        let engine = self.engine
        let brain = engine.socialBrain
        let userId = user.discordUserId
        let guildId = user.guildId
        let reasonText = reason.isEmpty ? "unspecified" : reason
        Task {
            await engine.performDestructiveAction(kind, targetUserId: userId, guildId: guildId, reason: reasonText) {
                await brain.penalize(userId: userId, guildId: guildId, reason: "\(kind.rawValue): \(reasonText)")
            }
        }
    }
}

#Preview("Users") {
    let engine = AbbeyStore.makePreviewEngine()
    UsersView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
