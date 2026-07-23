import SwiftUI
import SwiftData

struct UsersView: View {
    @Environment(AbbeyEngine.self) private var engine
    @Query(sort: \UserMemory.reputation, order: .reverse) private var users: [UserMemory]
    @State private var selectedUserID: PersistentIdentifier?
    @State private var search = ""

    private var filteredUsers: [UserMemory] {
        guard !search.isEmpty else { return users }
        return users.filter {
            $0.discordUserId.localizedCaseInsensitiveContains(search)
                || $0.guildId.localizedCaseInsensitiveContains(search)
                || $0.facts.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var selectedUser: UserMemory? {
        filteredUsers.first { $0.persistentModelID == selectedUserID } ?? users.first { $0.persistentModelID == selectedUserID }
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if filteredUsers.isEmpty {
                    ContentUnavailableView(
                        users.isEmpty ? "No users yet" : "No matches",
                        systemImage: "person.2",
                        description: Text(
                            users.isEmpty
                                ? "Ingest a message on the Dashboard to create UserMemory rows via SocialBrain."
                                : "Try a broader search."
                        )
                    )
                } else {
                    List(filteredUsers, selection: $selectedUserID) { user in
                        VStack(alignment: .leading) {
                            Text(user.discordUserId).font(.headline)
                            Text("guild: \(user.guildId) · rep: \(String(format: "%.2f", user.reputation)) · \(user.interactionCount) interactions · \(user.reputationEvents.count) events")
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
                } else {
                    ContentUnavailableView("Select a user", systemImage: "person")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Users")
        .searchable(text: $search, prompt: "User, guild, or fact")
    }
}

private struct UserDetailView: View {
    @Environment(AbbeyEngine.self) private var engine
    let user: UserMemory
    @Query private var events: [ReputationEvent]
    @State private var reason = ""
    @State private var newFact = ""

    init(user: UserMemory) {
        self.user = user
        let uid = user.discordUserId
        let gid = user.guildId
        _events = Query(
            filter: #Predicate<ReputationEvent> {
                $0.userId == uid && $0.guildId == gid
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
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
    return UsersView()
        .environment(engine)
        .modelContainer(engine.modelContainer)
}
