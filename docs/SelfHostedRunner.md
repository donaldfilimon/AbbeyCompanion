# Self-hosted macOS runner

The `Build & Test` job (`check`) in `.github/workflows/ci.yml` runs on a macOS arm64 runner registered to this repository. GitHub-hosted jobs can't start while the account's Actions billing is locked, but self-hosted jobs still run.

## Registration

| Field | Value |
|-------|-------|
| Labels | `self-hosted`, `macOS`, `ARM64`, `abbeycompanion` |
| Register at | [Settings → Actions → Runners → New self-hosted runner](https://github.com/donaldfilimon/AbbeyCompanion/settings/actions/runners/new?arch=arm64) (macOS, ARM64) |

A runner is registered to one repository. If the same Mac already runs a runner for another repository (for example `abi` or `gama`), install a second runner in its own directory (for example `~/actions-runner-abbeycompanion`), add the custom label `abbeycompanion` when `./config.sh` asks for extra labels, then run `./svc.sh install && ./svc.sh start`.

Until a runner with these labels is online, same-repo jobs wait in the queue.

## Host requirements

- Xcode 27. SwiftData macros ship only with Apple's toolchain, so a swiftly snapshot will not build this package. The job looks for `/Applications/Xcode-27.0.0.app`, `Xcode-27.0.0-beta.4.app`, `Xcode-27.0.0-beta.app`, then `Xcode.app`, and exports `DEVELOPER_DIR` for the first one it finds. If none exists, it uses whatever `xcode-select -p` reports.
- Xcode's license accepted and first-launch setup done once (`sudo xcodebuild -license accept`, `sudo xcodebuild -runFirstLaunch`), because the job itself never uses `sudo`.
- No Homebrew, Bun or other tools. The package has no external dependencies.

The job doesn't run `sudo xcode-select`, so it never changes the host's global Xcode selection.

## Security

This repository is public, so the self-hosted job runs only for `push` and for pull requests from branches in this repository. It also checks `github.repository == 'donaldfilimon/AbbeyCompanion'`, so forks of the repository never target the runner. Fork pull requests use the GitHub-hosted `check-hosted` job, `Build & Test (GitHub-hosted, fork PRs)`, which is an unchanged copy of the original job on `macos-27`. The checkout uses `persist-credentials: false`, and the workflow token is `contents: read`.

Where you can, use a dedicated macOS user for the runner rather than your daily account. Keep no production secrets on the host.

## Not covered

No job stays GitHub-hosted for trusted events: `check` was the only job. The fork-PR fallback `check-hosted` stays blocked until the billing lock is cleared.
