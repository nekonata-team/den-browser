---
name: fastlane-bump
description: Update a Bundler-pinned fastlane dependency in this repository, regenerate its lockfile, and validate fastlane lane loading.
---

# Fastlane Bump

Use for requests to update the fastlane version used by this repository.

## Workflow

1. Inspect `Gemfile`, `Gemfile.lock`, `fastlane/Fastfile`, and the worktree status.
2. Update the fastlane version in `Gemfile` to the user-provided target.
3. Run `bundle update fastlane` from the repository root. Let Bundler regenerate `Gemfile.lock`; do not hand-edit the lockfile.
4. Review the diff. Accept transitive dependency and checksum changes required by the target fastlane version, but reject unrelated source, configuration, or documentation changes.
5. Validate:
   - `bundle check`
   - `bundle exec fastlane --version` reports the target version
   - `bundle exec fastlane lanes` loads the repository lanes when `fastlane/Fastfile` exists
   - `git diff --check`
6. Recheck the final diff and report any validation that was skipped. Do not commit unless requested.

Keep dependency-only changes limited to `Gemfile` and `Gemfile.lock`. Run `just check` only when the change also touches Swift source, Xcode settings, or test configuration.

Do not add compatibility pins or special-case dependency workarounds without a reproducible resolver or runtime failure.
