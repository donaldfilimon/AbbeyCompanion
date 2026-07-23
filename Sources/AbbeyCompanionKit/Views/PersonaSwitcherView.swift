import SwiftUI

struct PersonaSwitcherView: View {
    @Environment(AbbeyEngine.self) private var engine
    @State private var currentPersonaName = "Abbey"
    @State private var testInput = ""
    @State private var lastResponse: PersonaResponse?
    @State private var isSending = false

    private let personas: [(name: String, color: Color, blurb: String)] = [
        ("Abbey", .green, "Direct, street-smart, reads people fast. Default register."),
        ("Aviva", .purple, "Analytical, structured, system-builder. Server arch, permissions, code."),
        ("Abi", .cyan, "Warm, adaptive, rapport-builder. Welcomes, tone-setting, de-escalation.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Active persona: \(currentPersonaName)")
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    ForEach(personas, id: \.name) { persona in
                        PersonaCard(
                            name: persona.name,
                            color: persona.color,
                            blurb: persona.blurb,
                            isActive: currentPersonaName == persona.name
                        ) {
                            Task {
                                await engine.personaRouter.setPersona(named: persona.name)
                                currentPersonaName = persona.name
                            }
                        }
                    }
                }

                Divider()

                Text("Test prompt").font(.headline)
                TextField("Say something to the active persona…", text: $testInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)

                HStack {
                    Button {
                        Task { await sendTestPrompt() }
                    } label: {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    Spacer()
                }

                if let response = lastResponse {
                    GroupBox("\(response.personaName) responded") {
                        Text(response.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Personas")
        .task {
            await refreshActivePersona()
        }
        .onChange(of: engine.lastEvent) {
            if case .personaSwitched(let name) = engine.lastEvent {
                currentPersonaName = name
            }
        }
    }

    private func refreshActivePersona() async {
        let active = await engine.personaRouter.currentPersona()
        currentPersonaName = active.name
    }

    private func sendTestPrompt() async {
        isSending = true
        defer { isSending = false }
        let persona = await engine.personaRouter.currentPersona()
        let response = await persona.respond(to: testInput, context: .empty, inference: engine.inferenceRouter)
        lastResponse = response
        currentPersonaName = response.personaName
        testInput = ""
    }
}

private struct PersonaCard: View {
    let name: String
    let color: Color
    let blurb: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Circle().fill(color).frame(width: 14, height: 14)
                Text(name).font(.headline)
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isActive ? color.opacity(0.15) : Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isActive ? color : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
