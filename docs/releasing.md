# Releasing Den Browser

Releases are notarized Developer ID builds published through the
`nekonata-team/homebrew-tap` Cask.

## One-time setup

1. Run `mise install` and `bundle install`.
2. Sign in with `gh auth login`.
3. Make the Developer ID certificate available through the private
   `nekonata-team/certificates` match repository.
4. Copy `.env.example` to `.env`. Keep the App Store Connect API key outside
   this repository and fill in:

   ```dotenv
   ASC_KEY_ID=...
   ASC_ISSUER_ID=...
   ASC_KEY_PATH=/absolute/path/to/AuthKey_....p8
   ```

## Prepare a candidate

Prepare the version bump and release candidate together:

```sh
just release prepare X.Y.Z
```

This requires a clean working tree, updates the marketing version and build
number, runs the checks, retrieves the Developer ID certificate from match,
builds a universal app, notarizes it, and writes the ZIP under
`.release/vX.Y.Z/`.

Review the Xcode project version change:

```sh
git diff "Den Browser/Den Browser.xcodeproj/project.pbxproj"
```

Extract the application from the ZIP and complete the applicable checks in
[poc.md](./poc.md).

Confirm that Gatekeeper accepts the app, it launches on Apple Silicon, and its
Profiles and Den state survive an upgrade. Confirm `codesign` reports Hardened
Runtime without the App Sandbox entitlement, the app contains arm64 and x86_64
Ghostty slices, and a Terminal Board can run the user's Shell. Remove the test
application before publishing.

## Prepare and publish without candidate verification

When manual candidate verification is not required, run the complete release:

```sh
just release ship X.Y.Z
```

This requires a clean `main` worktree, runs `prepare`, and then runs `publish`
without stopping for candidate verification. The command asks for one
confirmation before starting; pass `--yes` only when the whole release is
intentionally non-interactive:

```sh
just --yes release ship X.Y.Z
```

If either phase fails, the command stops immediately. Use the component
commands below to inspect and continue a partial release.

## Publish

After verifying the candidate, publish it:

```sh
just release publish X.Y.Z
```

This commits and pushes the version change, creates and pushes the annotated
tag, creates a GitHub Release with the notarized ZIP artifact and links to the
tagged source, MPL 2.0 license, and third-party notices in its release notes,
opens the Homebrew Cask pull request, and enables rebase auto-merge.

All orchestration commands stop at the first failure. The component commands
remain available:

```sh
just release set-version X.Y.Z
just release candidate vX.Y.Z
just release github vX.Y.Z
just release homebrew X.Y.Z
```

After a partial publish, inspect what already exists before using a component
command to continue. Do not delete or replace a tag, Release, artifact, or pull
request.

### Homebrew (First-time setup)

Follow [this](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).
