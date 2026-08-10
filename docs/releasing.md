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

## Publish

After verifying the candidate, publish it:

```sh
just release publish X.Y.Z
```

This commits and pushes the version change, creates and pushes the annotated
tag, creates a GitHub Release with the notarized ZIP artifact, opens the
Homebrew Cask pull request, and enables rebase auto-merge. Release notes are
intentionally left empty.

Both orchestration commands stop at the first failure. The component commands
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
