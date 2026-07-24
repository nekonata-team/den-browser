---
name: release-den-browser
description: Release a Den Browser version through its project-defined signed and notarized macOS flow. Use when asked to release, publish, or prepare a Den Browser version, including version bump, release candidate, git tag, GitHub Release, and Homebrew Cask update.
---

# Release Den Browser

Use repository `just` recipes. Keep execution centered on four commands:

```sh
just set-version X.Y.Z
just release-candidate vX.Y.Z
just release vX.Y.Z
just bump-homebrew X.Y.Z
```

## Failure policy

Stop immediately when any command or validation fails. Do not fix, retry,
roll back, clean up, or manually complete the release without a new explicit
user instruction.

Use read-only checks only as needed to report:

- failed command and shortest decisive error
- last successful step
- local and remote commit, tag, Release, artifact, and PR state
- safe next options for the user

Never delete or replace a tag, Release, artifact, or PR after a partial
release.

## Plan

Before changing state, show this sequence with the concrete version:

1. Bump version.
2. Build, test, sign, notarize, and package candidate.
3. Confirm upgrade behavior, then commit and push `main`.
4. Publish GitHub Release.
5. Open Homebrew Cask PR.
6. Show all release links and identifiers together.

## Preflight

1. Read `docs/releasing.md`.
2. Run `just --list`.
3. Require `main`, a clean worktree, and no existing target tag or GitHub Release.
4. Confirm `gh auth status`, Bundler dependencies, `.env`, and required App Store Connect variables exist. Never print secret values.
5. Confirm `main` is synchronized with `origin/main`. Stop on unexpected local or remote commits.

## Execute

### 1. Bump

Run:

```sh
just set-version X.Y.Z
```

Inspect the Xcode project diff. Require only expected marketing-version and build-number changes.

### 2. Candidate

Run:

```sh
just release-candidate vX.Y.Z
```

Do not run separate checks already covered by this recipe. Require successful unit tests, UI tests, signing, notarization, stapling, and Gatekeeper assessment.

Before publishing, ask the user to confirm the candidate launches on Apple Silicon and existing Profiles and Den state survive the upgrade. Treat an explicit instruction to continue as confirmation.

### 3. Commit and push

Only after candidate success and upgrade confirmation:

```sh
git add "Den Browser/Den Browser.xcodeproj/project.pbxproj"
git commit -m "bump: バージョンを更新"
git push origin main
```

Require a clean worktree and synchronized `main` before publishing.

### 4. Publish

Run:

```sh
just release vX.Y.Z
```

If publication fails after tag creation, inspect state read-only, report
exactly what exists, and stop.

### 5. Distribute

Run:

```sh
just bump-homebrew X.Y.Z
```

This recipe creates the Homebrew PR without opening a browser and enables
rebase auto-merge. Verify the PR exists and report whether it is waiting for
required checks or already merged.

## Final report

Show together:

- GitHub Release URL
- Homebrew PR URL
- Homebrew PR auto-merge or merged state
- release commit SHA
- tag
- candidate ZIP path
- SHA-256
- unit/UI test, notarization, stapling, and Gatekeeper results
- final worktree and `origin/main` synchronization state

Report a partial release precisely. Do not claim completion while any publish
or distribution step remains. Stop and wait for user direction after every
failure.
