# AbbeyCompanion

Native macOS SwiftUI companion for Abbey Bot. **Swift 6.4** / SwiftData / SwiftUI —
no Vapor, no Fluent, no network required in `.deterministicFloor` mode.

## Requirements

| | |
|--|--|
| Swift | 6.4+ (Xcode 27 / `swift-tools-version: 6.4`) |
| Platform | macOS 26+ (`.macOS(.v26)`) |
| Modules | `AbbeyCore` · `AbbeyCompanionKit` (engine/UI) · `AbbeyCompanion` app |

## Run

```bash
./scripts/check.sh   # build + AbbeyCoreTests + AbbeyCompanionKitTests
./scripts/smoke.sh   # check + assert binary exists
./scripts/run.sh     # launch app
```

CI: `.github/workflows/ci.yml` (macos-26 + Xcode 27 when available).

## Feature map

| Surface | What it does |
|---------|----------------|
| Dashboard | Ingest → channel upsert → reputation → DQN → persona/inference → reply |
| Intents | greeting, question, command, memoryStore, repQuery, personaSwitch, **modRequest** (`!kick`/`!ban`/`!purge`) |
| DQN | 18→8 projection; ignore / reply / escalate; **checkpoint persistence**; learn batch 8 |
| Reactions | Messages 👍/👎 credits delayed reward against stored policy (once per turn) |
| Batch | Dashboard **transcript replay** (multi-line; `#` comments skipped) |
| Users | Reputation history; **facts CRUD**; purge / kick / ban via ConfirmationGate |
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
- Partial from-source `swift-project` builds without `swift-run` are gated out of `PATH`
  in `~/.zshrc`; prefer `./scripts/run.sh` anyway.
