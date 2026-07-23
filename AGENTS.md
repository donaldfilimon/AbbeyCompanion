# AbbeyCompanion

## What this is

SwiftPM package with four targets:
- **AbbeyCore** — cross-platform library (DQN, sentiment, intent classifier, equity screen). Flat layout, all `public`.
- **AbbeyCompanionKit** — macOS library (engine, SwiftData models, inference providers, personas, SwiftUI views). `package` access for cross-target use.
- **CoreAITools** — macOS library merged from CoreAIAssistant (conversation/AI assistant UI, MCP client, plugin system, file services, ACP client). `package` access.
- **AbbeyCompanion** — thin macOS app shell (`@main`, commands, notifications).

Swift 6.4 / `.swiftLanguageMode(.v6)` strict concurrency. macOS 27+ (`.macOS(.v27)`).

**Toolchain requirement**: SwiftData macros (`@Query`, `@Model`) ship only with **Xcode’s** toolchain. Open-source swiftly snapshots (`main-snapshot` / 6.5-dev) lack `libSwiftDataMacros` — selecting them in **CLI or Xcode → Toolchains** yields `unknown attribute 'Query'`. This repo pins `.swift-version` to `xcode` (`swiftly use xcode`) so PATH `swift` is Xcode 6.4 while the global swiftly default can remain a snapshot. Scripts unset `TOOLCHAINS` and fall back to `XcodeDefault.xctoolchain` if PATH is still a snapshot.

## Commands

| What | Command | Notes |
|------|---------|-------|
| Build + test (all) | `./scripts/check.sh` | Xcode-backed Swift (`.swift-version` → `xcode` or `XcodeDefault` fallback). |
| Build + test + binary check | `./scripts/smoke.sh` | check.sh + asserts binary exists under `.build/`. |
| Build + run app | `./scripts/run.sh` | Builds and launches AbbeyCompanion. |
| Build only | `swift build` | Works when `.swift-version` is `xcode`; else `./scripts/check.sh` / `xcrun swift build`. |
| Test only | `swift test` | 81 tests (43 CoreAITools + 12 AbbeyCore + 26 AbbeyCompanionKit). Prefer `./scripts/check.sh`. |

## Structure

```
Sources/
├── AbbeyCore/                    # Platform-neutral, all files flat
│   ├── DQNAgent.swift            # Online + target networks, checkpoint persistence
│   ├── NeuralNetwork.swift       # SIMD8-based forward/backprop, Snapshot type
│   ├── IntentClassifier.swift    # classify / classifyStrict / suggestCompletions / parseModCommand
│   ├── SentimentAnalyzer.swift   # 18-dim state, projectToNetworkInput (→8-dim)
│   ├── ReplayBuffer.swift        # O(1) fixed-capacity ring
│   ├── FactorScreen.swift        # Fictional QX-#### equity scoring
│   └── MirrorExportDocument.swift# Codable JSON round-trip
├── AbbeyCompanionKit/            # macOS library (package access)
│   ├── App/                      # AbbeyEngine, AbbeyPersistence, AppConfig, AbbeyNotifications
│   ├── Engine/                   # EventBus, AbbeyScheduler, SocialBrain, ConfirmationGate, AbbeySlashCommands
│   ├── Inference/                # DeterministicFloor, FoundationModels, RemoteOpenAI, OnDeviceModelProbe
│   ├── Models/                   # SwiftData: AbbeyStore, GuildMessage, UserMemory, ChannelContext, etc.
│   ├── Personas/                 # Persona protocol, Abbey/Aviva/ABI, ABIRouter
│   └── Views/                    # AbbeyRootView (AI slot injected), Dashboard, Messages, Users, Settings, …
├── CoreAITools/                  # macOS library merged from CoreAIAssistant (package access)
│   ├── Views/                    # AssistantRootView, ChatView, SidebarView, WelcomeView, InspectorView
│   ├── Stores/                   # ConversationStore + ConversationStoreBootstrap + streaming/slash extensions
│   ├── Services/                 # AIService, FileTreeService, FileWatcherService, ACPClient, MCPClient
│   ├── Tools/                    # File/Search/Command/Git tools
│   └── Support/                  # SlashCommands, PathSecurity, Appearance, …
└── AbbeyCompanionApp/            # Thin @main shell + AbbeyCommands + AIAssistantView (wires CoreAITools)
Tests/
├── AbbeyCoreTests/               # 12 tests (Swift Testing @Suite/@Test)
├── AbbeyCompanionKitTests/       # Ingest / Engine / Bridge suites (+ shared AbbeyKitTestSupport)
└── CoreAIToolsTests/             # 43 tests (appearance, persistence, security, ACP, MCP, slash commands, etc.)
scripts/
├── lib.sh                        # Shared Xcode Swift resolution (`.swift-version` / XcodeDefault)
├── check.sh                      # Build + test (Xcode toolchain)
├── run.sh                        # Build + launch app
└── smoke.sh                      # check + binary existence assert
Makefile                          # check / smoke / run → scripts/
```

## Key gotchas

- **Toolchain**: SwiftData needs XcodeDefault. Pin with `swiftly use xcode` (`.swift-version`). In Xcode: **Toolchains → Xcode Default**, not Development Snapshot. OSS 6.5-dev snapshots fail `@Query` in CLI and Xcode alike. Scripts: `./scripts/check.sh` / `lib.sh`.
- **Four-target dependency chain**: `AbbeyCompanion → AbbeyCompanionKit → AbbeyCore` and `AbbeyCompanion → CoreAITools` (app composes both). Kit does **not** depend on CoreAITools. CoreAITools depends on AbbeyCore for DQN/NeuralNetwork types.
- **AbbeyCompanionKit + CoreAITools use `package` access** — not `internal`, not `public`. This lets the app target and test target import them while keeping the API boundary tight.
- **AbbeyEngine is the thin orchestrator** — wires EventBus, SocialBrain, DQN, Scheduler, ConfirmationGate, personas, inference. Persistence is `AbbeyPersistence`; bang/slash companion commands are `AbbeySlashCommands`.
- **ConfirmationGate suspends at the call site** via `CheckedContinuation` — destructive actions (purge/kick/ban) block until the user confirms or cancels.
- **Inference**: Default is `.deterministicFloor` (no model, no network). On-device requires Apple Foundation Models hardware (macOS 27+). Remote uses OpenAI-compatible `/chat/completions`.
- **DQN uses SIMD8** for forward pass and backprop with a fixed 8-dim input (`projectToNetworkInput`). `NeuralNetwork.Snapshot` and `DQNAgent.Checkpoint` support persistence.
- **SwiftData models**: `AbbeyStore` is the centralized schema factory. Models use `@Model` with relationships (UserMemory ↔ ReputationEvent, ChannelContext ↔ GuildMessage).
- **Equity module uses fictional instruments only** (`QX-####` synthetic data).
- **Tests use Swift Testing** (`@Suite` / `@Test`), not XCTest.
- **DQN hyperparameters** (gamma, epsilon, learning rate, batch size) are exposed in `AppConfig` and tunable via `SettingsView` sliders/steppers.
- **Keyboard shortcuts**: Cmd+1…9 for all 9 sidebar sections (including `.aiAssistant` at Cmd+9), Navigate menu with shortcut reference at Cmd+Shift+/.
- **Window state persistence**: Sidebar selection + window size via `@AppStorage`.
- **Appearance customization**: Accent color + font size pickers in Settings.
- **Batch operations**: Messages view supports multi-select delete.
- **QuickIngestPanel**: Floating ingest bar in Dashboard via `.safeAreaInset`.
- **CoreAITools integration**: App-hosted `AIAssistantView` builds a `ConversationStoreBootstrap` (project path + persona/inference prompt) and embeds `AssistantRootView(bootstrap:)`. `AbbeyRootView` takes the assistant as a `@ViewBuilder` slot so root view names never collide.

## CI

GitHub Actions (`.github/workflows/ci.yml`) on `macos-27`:
1. Select Xcode 27
2. `./scripts/check.sh` (build + all 3 test suites)

Branch filter: `main` + `cursor/**`.
