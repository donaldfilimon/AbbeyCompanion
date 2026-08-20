> ## ⚠️ RETIRED — 2026-08-20
>
> **This repository is retired. Its code now lives in `~/dev/active/CoreAIAssistant`.**
>
> AbbeyCompanion was a fork of CoreAIAssistant: its `CoreAITools` target shared 40 files
> by identical relative path with CoreAIAssistant's app core (28 byte-identical, and of the
> 12 that diverged, 9 were newer on the CoreAIAssistant side). On 2026-08-20 CoreAIAssistant
> was declared canonical and this repo's unique work was ported into it:
>
> | Was here | Now lives in CoreAIAssistant as |
> |---|---|
> | `Sources/AbbeyCore` (7 files) + `Tests/AbbeyCoreTests` (12 tests) | `AbbeyCore` target + `.library` product, ported verbatim |
> | `Sources/AbbeyCompanionKit` (45 files) + `Tests/AbbeyCompanionKitTests` (27 tests) | `AbbeyCompanionKit` target + `.library` product, ported verbatim |
> | `CoreAITools`' `ConversationStoreBootstrap` and `AssistantRootView` | cherry-picked into the `CoreAIAssistant` executable target |
> | `CoreAITools`' `ConversationFileChangeTracker` and `GitRunner.approvedRun` | cherry-picked into the `CoreAIAssistant` executable target |
>
> Everything else in `CoreAITools` was either byte-identical to, a file-split of, or older
> than CoreAIAssistant's copy, and was intentionally not carried over. All 43 of this repo's
> `CoreAIToolsTests` were verified to be a strict subset of CoreAIAssistant's 60.
>
> **Do not fix bugs or add features here — do it in `~/dev/active/CoreAIAssistant`.**
> Rationale and full port record:
> `~/dev/active/CoreAIAssistant/docs/superpowers/specs/2026-08-20-abbeycompanion-canonicalization-design.md`
>
> The repo stays in `~/dev/archive/` as history. The text below describes it as it was.

---

# AbbeyCompanion

Native macOS SwiftUI companion for Abbey Bot. **Swift 6.4** / SwiftData / SwiftUI —
no Vapor, no Fluent, no network required in `.deterministicFloor` mode.

## Requirements

| | |
|--|--|
| Swift | **Xcode 27 bundled Swift 6.4** (SwiftData macros). Pin with `swiftly use xcode` |
| Platform | macOS 27+ (`.macOS(.v27)`) |
| Modules | `AbbeyCore` · `AbbeyCompanionKit` · `CoreAITools` · `AbbeyCompanion` app |
| Store | `AbbeyStore` schema factory · relationships (`UserMemory`↔`ReputationEvent`, `ChannelContext`↔`GuildMessage`) |

> **SwiftData vs swiftly snapshots:** `main-snapshot` / **6.5-dev** (OSS toolchains) do **not** ship `libSwiftDataMacros`. Using them — from PATH **or** Xcode → Toolchains → Development Snapshot — fails with `unknown attribute 'Query'`. This repo pins `.swift-version` → `xcode` so PATH `swift` (via swiftly) is Xcode’s 6.4 while your **global** swiftly default can stay on a snapshot.
>
> **Xcode UI:** menu **Xcode → Toolchains → Xcode Default** (not the Development Snapshot). Snapshots appear because swiftly installs into `~/Library/Developer/Toolchains/`.

## Run

```bash
swiftly use xcode     # once per clone — writes .swift-version (already present)
./scripts/check.sh    # build + all 3 test suites
./scripts/smoke.sh    # check + assert binary exists
./scripts/run.sh      # launch app
# or, with .swift-version pinned:
swift build && swift test && swift run
```

CI: `.github/workflows/ci.yml` (`macos-27` + Xcode 27).

## Feature map

| Surface | What it does |
|---------|----------------|
| Dashboard | Ingest → channel upsert → reputation → DQN → persona/inference → reply |
| AI Assistant | App-hosted CoreAI `AssistantRootView` via `ConversationStoreBootstrap` (persona + inference) |
| Intents | greeting, question, command, memoryStore, repQuery, personaSwitch, **modRequest** (`!kick`/`!ban`/`!purge`) |
| DQN | 18→8 projection; ignore / reply / escalate; **checkpoint persistence**; learn batch 8 |
| Reactions | Messages 👍/👎 credits delayed reward against stored policy (once per turn) |
| Batch | Dashboard **transcript replay** (multi-line; `#` comments skipped) |
| Users | Reputation history (live relationship query); **search** user/guild/fact; facts CRUD; mod actions |
| Messages | **Channel chip filter** (`@Query` + Capsule chips); search; 👍/👎 policy rewards |
| Handoff | Seed demo · JSON export/import · autocomplete · live event feed |
| Settings | Remote probe · Foundation Models status · strict intent · **reset DQN weights** |

## Config knobs (`AppConfig` / Settings)

`ABBEY_OPERATING_MODE` · `ABBEY_INFERENCE_MODE` · `ABBEY_REMOTE_ENDPOINT` ·
`ABBEY_REMOTE_API_KEY` · `ABBEY_REMOTE_MODEL` · `ABBEY_REPLY_COOLDOWN_SECONDS` ·
`ABBEY_MEMORY_CONSOLIDATION_INTERVAL_MIN` · `ABBEY_REPUTATION_DECAY` ·
`ABBEY_CONFIRMATION_REQUIRED` · `ABBEY_EQUITY_MODULE_ENABLED` ·
`ABBEY_USE_STRICT_INTENT` · `ABBEY_ABSTRACTIVE_CONSOLIDATION`

## Slash commands (Dashboard ingest)

`!help` · `!rep [user]` · `!persona [name]` · `!status` · `!consolidate` ·
`!kick|!ban|!purge <user> [reason]`

Menu: **Abbey ▸ Seed Demo Data** · **Consolidate Channels Now** · **Reset Local Store**

## Notes

- Default inference is `.deterministicFloor` (fully offline).
- Open decisions still flagged in code: softmax-on-Q vs logits (DQN uses logits);
  `.unknown` reachability (`classify` vs `classifyStrict`).
