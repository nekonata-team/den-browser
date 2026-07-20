set shell := ["zsh", "-cu"]

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
swift_format := "xcrun swift-format"
swift_sources := "Den Browser"
fastlane := "bundle exec fastlane"

_validate-version $version:
    [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'usage: version must be X.Y.Z'; exit 1; }

_validate-tag $tag:
    [[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'usage: tag must be vX.Y.Z'; exit 1; }

# Format all Swift sources in place.
[group("quality")]
format:
    {{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{swift_sources}}"

# Fail on Swift style and safety findings.
[group("quality")]
lint:
    {{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{swift_sources}}"

# Build macOS app without code signing.
[group("build")]
build:
    xcodebuild build -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" CODE_SIGNING_ALLOWED=NO

# Bind SourceKit-LSP to this Xcode project.
[group("development")]
lsp-config:
    xcode-build-server config -project "{{project}}" -scheme "{{scheme}}"

# Build and launch the application locally.
[group("development")]
run: build
    open "{{derived_data}}/Build/Products/Debug/Den Browser.app"

# Remove all derived data build directories.
[group("development")]
clean:
    rm -rf "{{derived_data}}"

[group("development")]
precommit:
    lefthook run pre-commit

[group("development")]
prepush:
    lefthook run pre-push

# Run unit tests without code signing.
[group("test")]
test:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" -only-testing:'Den BrowserTests' CODE_SIGNING_ALLOWED=NO

# Run deterministic macOS UI interaction tests. Pass a target to run a specific class or case (e.g. just ui-test Den_BrowserUITests/testNewBoardIsCenteredAfterCreation).
[group("test")]
ui-test target="":
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" -only-testing:"Den BrowserUITests{{ if target == "" { "" } else { "/" + target } }}"

# Build then run unit tests.
[group("test")]
check: lint build test

# Set version and auto-increment build number via Fastlane.
[group("release")]
set-version version: (_validate-version version)
    {{fastlane}} bump_version version:{{version}}

# Build, sign, notarize, and package a release candidate without publishing it.
[group("release")]
release-candidate tag: (_validate-tag tag)
    {{fastlane}} release_candidate tag:{{tag}}

# Publish a tested release candidate to GitHub.
[group("release")]
[script]
release $tag: (_validate-tag tag)
    set -euo pipefail

    [[ -z "$(git status --porcelain)" ]] || {
        print -u2 "working tree has uncommitted changes"
        exit 1
    }

    version="${tag#v}"
    archive="Den-Browser-${version}-macOS.zip"
    zip=".release/${tag}/${archive}"

    [[ -f "$zip" ]] || {
        print -u2 "missing candidate: $zip"
        exit 1
    }

    git tag -a "$tag" -m "Den Browser $version"
    git push origin "$tag"

    gh release create "$tag" "$zip" \
        --repo nekonata-team/den-browser \
        --verify-tag \
        --title "$tag" \
        --notes ""

# Update the Homebrew Cask through a pull request.
[group("release")]
[script]
bump-homebrew $version: (_validate-version version)
    set -euo pipefail

    brew tap nekonata-team/tap

    brew bump-cask-pr \
        --version "$version" \
        --no-fork \
        nekonata-team/tap/den-browser
