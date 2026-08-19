# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` — it is the canonical, up-to-date guide for this repo (stack, commands, architecture, gotchas). Follow it exactly.

Archived: this repo lives under `~/dev/archive` — report-only; do not refactor.

Quick anchors:
- **Stack**: SwiftPM macOS app, Swift 6.4 strict concurrency, macOS 27+; four targets `AbbeyCore` -> `AbbeyCompanionKit` / `CoreAITools` -> `AbbeyCompanion` app shell (SwiftData + SwiftUI).
- Build + test: `./scripts/check.sh` · smoke: `./scripts/smoke.sh` · run: `./scripts/run.sh` · (`swift build` / `swift test` work when `.swift-version` is `xcode`).
- Toolchain: SwiftData macros need Xcode's toolchain — `swiftly use xcode`; OSS snapshots fail with `unknown attribute 'Query'`.
- `AbbeyCompanionKit` + `CoreAITools` use `package` access; Kit does not depend on CoreAITools. Tests use Swift Testing (`@Suite`/`@Test`), not XCTest.
