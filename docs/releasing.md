# Releasing Den Browser

Releases are notarized Developer ID builds published through the
`nekonata-team/homebrew-tap` Cask and the Sparkle Appcast.

## One-time setup

1. Run `mise install` and `bundle install`.
2. Sign in with `gh auth login`.
3. Make the Developer ID certificate available through the private
   `nekonata-team/certificates` match repository.
4. Resolve the Xcode package once. This creates the project-local Sparkle tools
   under `.derived-data/`:

   ```sh
   just build
   ```

5. Generate the Sparkle EdDSA key once:

   ```sh
   just release generate-key
   ```

   Keep the private key in the login Keychain. Never commit or print it. Add
   the generated public key to `Den-Browser-Info.plist` as `SUPublicEDKey`.
6. Copy `.env.example` to `.env`. Keep the App Store Connect API key outside
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
number, runs the release checks, retrieves the Developer ID certificate from
match, builds a universal app, notarizes it, writes the ZIP under
`.release/vX.Y.Z/`, and generates `web/public/appcast.xml` from that candidate.

The release checks run before the artifact pipeline: `just check` runs first,
then `just ui-test`. Fastlane owns only signing, archiving, exporting,
notarizing, and packaging. A retry of `just release candidate X.Y.Z` after a
Fastlane failure does not repeat the release checks; run `just release verify`
again when source or version inputs change.

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

If either phase fails, the command stops immediately.

## Publish

After verifying the candidate, publish it:

```sh
just release publish X.Y.Z
```

This commits and pushes the version change and Appcast, creates and pushes the
annotated tag, creates a GitHub Release with the notarized ZIP artifact and
links to the tagged source, MPL 2.0 license, and third-party notices in its
release notes, then opens the Homebrew Cask pull request and enables rebase
auto-merge.

The Appcast is generated during `prepare`, but `publish` pushes the `main`
commit only after the GitHub Release exists. This prevents the live Appcast
from advertising a download URL before the corresponding asset is available.

The Appcast points to the versioned ZIP attached to the GitHub Release. Sparkle
signs the ZIP with the EdDSA key from the login Keychain. Cloudflare Pages then
serves the Appcast at `https://den.nekonata.dev/appcast.xml`.

The Homebrew Cask must declare `auto_updates true` because the installed app
can update itself through Sparkle. This change belongs in the external
`nekonata-team/homebrew-tap` repository.

The first Sparkle-enabled release is a bootstrap release. Users running an
older direct-download build must install that release once manually; later
releases can update through Sparkle.

If a release stops midway, inspect what already exists before resuming. Do not
delete or replace a tag, Release, artifact, or pull request.

### Homebrew (First-time setup)

Follow [this](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).
