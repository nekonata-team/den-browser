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

1. Set the new marketing version and auto-increment the build number using:

   ```sh
   just set-version X.Y.Z
   ```

2. Review the modifications to the Xcode project configuration and commit them:

   ```sh
   git diff "Den Browser/Den Browser.xcodeproj/project.pbxproj"
   git commit -am "Release vX.Y.Z"
   git push origin main
   ```

3. Build and package the release candidate:

   ```sh
   just release-candidate vX.Y.Z
   ```

This runs the checks, retrieves the Developer ID certificate from match, builds a universal app, notarizes it, and writes the ZIP under `.release/vX.Y.Z/`.

Extract the application from the ZIP and complete the applicable checks in
[poc.md](./poc.md).

Confirm that Gatekeeper accepts the app, it launches on Apple Silicon, and its
Profiles and Den state survive an upgrade. Remove the test application before publishing.


## Publish

Publish the GitHub Release:

```sh
just release vX.Y.Z
```

This creates the annotated git tag, pushes it to `origin`, and creates a GitHub Release with the notarized ZIP artifact. Release notes are intentionally left empty.

If publishing the GitHub Release fails after the tag is created, inspect the completed steps and finish the remaining GitHub Release creation manually. Do not delete or replace published artifacts.

## Distribute

Once the GitHub Release is published and the ZIP is publicly accessible, distribute the version to external package managers (Homebrew).

### Homebrew (First-time setup)

Follow [this](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

### Homebrew (Subsequent releases)

For subsequent releases, run the following command to submit a pull request updating the Cask:

```sh
just bump-homebrew vX.Y.Z
```

This uses `brew bump-cask-pr` to automatically update the version and SHA-256 of the Cask on the tap repository.
