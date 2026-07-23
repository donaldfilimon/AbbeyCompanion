import SwiftUI

package struct AboutView: View {
    package init() {}

    package var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Abbey Companion")
                .font(.title.bold())
            Text("Swift 6.4 · macOS 26+ · AbbeyCore + SwiftUI")
                .foregroundStyle(.secondary)
            Text("Standalone companion for Abbey Bot. Local SwiftData only — no Discord gateway, no Postgres sync.")
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Group {
                labeled("Intents", "greeting · question · memory · rep · persona · mod · commands")
                labeled("Inference", "deterministicFloor · onDevice · remote OpenAI-compatible")
                labeled("DQN", "18→8 · ignore/reply/escalate · checkpoint + 👍/👎 rewards")
                labeled("Handoff", "JSON export/import · batch transcript replay")
            }
            .font(.caption)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 420, height: 280)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).bold().frame(width: 72, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
        }
    }
}
