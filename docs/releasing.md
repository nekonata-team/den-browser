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

## Create a candidate

Update and commit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, then push
`main`. The version must match the tag without its `v` prefix.

```sh
just release-candidate v0.1.0
```

This runs the checks and UI tests, retrieves the Developer ID certificate,
builds a universal app, notarizes it, and writes the ZIP and a local Cask under
`.release/v0.1.0/`.

Install the candidate through Homebrew and complete the applicable checks in
[poc.md](./poc.md):

```sh
brew install --cask ./.release/v0.1.0/den-browser-local.rb
```

Confirm that Gatekeeper accepts the app, it launches on Apple Silicon, and its
Profiles and Den state survive an upgrade. Do not use `--zap` with data that
must be preserved. Uninstall the local Cask before publishing.

## Publish

```sh
just release v0.1.0
```

The command shows the latest published version and SHA-256 before asking once
for confirmation. It enables immutable GitHub Releases, creates the annotated
tag and GitHub Release, validates the Cask with Homebrew, then pushes the Cask
directly to the Tap's `main` branch. Release notes are intentionally empty.

If publishing fails after the tag or GitHub Release is created, do not delete
or replace published artifacts. Inspect the completed step and finish the
remaining GitHub or Tap operation manually.
