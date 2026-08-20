# CLAUDE.md

> ## ⚠️ RETIRED — 2026-08-20. Canonical home is `~/dev/active/CoreAIAssistant`.
>
> This repo was a fork of CoreAIAssistant. On 2026-08-20 its unique code was ported into
> CoreAIAssistant, which is now canonical:
>
> - `AbbeyCore` (7 files, 12 tests) and `AbbeyCompanionKit` (45 files, 27 tests) were ported
>   verbatim as library targets of `~/dev/active/CoreAIAssistant`.
> - From `CoreAITools`, only `ConversationStoreBootstrap`, `AssistantRootView`,
>   `ConversationFileChangeTracker`, and `GitRunner.approvedRun` were genuinely new; they were
>   cherry-picked into CoreAIAssistant's executable target. The rest was byte-identical to,
>   a file-split of, or older than CoreAIAssistant's copy.
> - All 43 `CoreAIToolsTests` here are a strict subset of CoreAIAssistant's 60 by test-function
>   name — superseded, not lost.
>
> **Do not fix bugs or add features here.** Make the change in `~/dev/active/CoreAIAssistant`.
> Full port record and rationale:
> `~/dev/active/CoreAIAssistant/docs/superpowers/specs/2026-08-20-abbeycompanion-canonicalization-design.md`
>
> The guidance below is retained for reading this repo's history.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` — it is the canonical, up-to-date guide for this repo (stack, commands, architecture, gotchas). Follow it exactly.

Archived: this repo lives under `~/dev/archive` — report-only; do not refactor.

Quick anchors:
- **Stack**: SwiftPM macOS app, Swift 6.4 strict concurrency, macOS 27+; four targets `AbbeyCore` -> `AbbeyCompanionKit` / `CoreAITools` -> `AbbeyCompanion` app shell (SwiftData + SwiftUI).
- Build + test: `./scripts/check.sh` · smoke: `./scripts/smoke.sh` · run: `./scripts/run.sh` · (`swift build` / `swift test` work when `.swift-version` is `xcode`).
- Toolchain: SwiftData macros need Xcode's toolchain — `swiftly use xcode`; OSS snapshots fail with `unknown attribute 'Query'`.
- `AbbeyCompanionKit` + `CoreAITools` use `package` access; Kit does not depend on CoreAITools. Tests use Swift Testing (`@Suite`/`@Test`), not XCTest.
