set shell := ["zsh", "-cu"]

fastlane := "bundle exec fastlane"

_validate-version $version:
    @[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { printf '%s\n' 'usage: version must be X.Y.Z' >&2; exit 1; }

_require-main:
    @[[ "$(git branch --show-current)" == main ]] || { printf '%s\n' 'release must run on main' >&2; exit 1; }

_require-clean:
    @[[ -z "$(git status --porcelain)" ]] || { printf '%s\n' 'working tree has uncommitted changes' >&2; exit 1; }

[private]
[script]
_sparkle-tools:
    set -euo pipefail

    tools="${SPARKLE_TOOLS:?SPARKLE_TOOLS is not set}"
    [[ -x "$tools/generate_keys" && -x "$tools/generate_appcast" ]] || {
        printf '%s\n' "Sparkle tools not found at $tools; run just build first." >&2
        exit 1
    }
    printf '%s\n' "$tools"

[script]
_commit-version-if-needed:
    set -euo pipefail

    git add "Den Browser/Den Browser.xcodeproj/project.pbxproj"
    git add web/public/appcast.xml

    if git diff --cached --quiet -- "Den Browser/Den Browser.xcodeproj/project.pbxproj" web/public/appcast.xml; then
        printf '%s\n' 'version unchanged; skipping commit'
    else
        git commit -m "bump: バージョンを更新" -- "Den Browser/Den Browser.xcodeproj/project.pbxproj" web/public/appcast.xml
    fi

# Set version and auto-increment build number.
set-version version: (_validate-version version)
    {{fastlane}} bump_version version:{{version}}

# Build, sign, notarize, and package a release candidate.
candidate version: (_validate-version version)
    {{fastlane}} release_candidate tag:v{{version}}

# Run release checks before signing and packaging.
[script]
verify:
    just check
    just ui-test

# Generate the Sparkle EdDSA key in the login Keychain.
[confirm("Generate Sparkle EdDSA key in the login Keychain?")]
[script]
generate-key:
    set -euo pipefail
    tools="$(just release _sparkle-tools)"
    "$tools/generate_keys"

# Generate the Appcast for a release candidate archive.
[script]
appcast version: (_validate-version version)
    set -euo pipefail

    version="{{version}}"
    tag="v${version}"
    zip=".release/${tag}/Den-Browser-${version}-macOS.zip"
    input=".release/${tag}/appcast-input"
    [[ -f "$zip" ]] || { printf '%s\n' "missing candidate: $zip" >&2; exit 1; }

    mkdir -p "$input"
    cp "$zip" "$input/"
    tools="$(just release _sparkle-tools)"
    "$tools/generate_appcast" --download-url-prefix "https://github.com/nekonata-team/den-browser/releases/download/${tag}/" --full-release-notes-url "https://github.com/nekonata-team/den-browser/releases/tag/${tag}" --link "https://den.nekonata.dev/" -o "web/public/appcast.xml" "$input"
    xmllint --noout web/public/appcast.xml

# Publish a tested release candidate to GitHub.
[confirm("Publish candidate to GitHub?")]
[script]
github version: (_validate-version version)
    set -euo pipefail

    version="{{version}}"
    tag="v${version}"
    [[ -z "$(git status --porcelain)" ]] || {
        printf '%s\n' "working tree has uncommitted changes" >&2
        exit 1
    }

    zip=".release/${tag}/Den-Browser-${version}-macOS.zip"

    [[ -f "$zip" ]] || {
        printf '%s\n' "missing candidate: $zip" >&2
        exit 1
    }

    source_url="https://github.com/nekonata-team/den-browser/tree/${tag}"
    notes="Source code and licensing:"
    notes+=$'\n\n'
    notes+="- [Source code](${source_url})"
    notes+=$'\n'
    notes+="- [MPL 2.0 license](${source_url}/LICENSE)"
    notes+=$'\n'
    notes+="- [Third-party notices](${source_url}/THIRD_PARTY_NOTICES.md)"

    git tag -a "$tag" -m "Den Browser $version"
    git push origin "$tag"

    gh release create "$tag" "$zip" \
        --repo nekonata-team/den-browser \
        --verify-tag \
        --title "$tag" \
        --notes "$notes"

# Update the Homebrew Cask and enable auto-merge.
[confirm("Update Homebrew Cask?")]
[script]
homebrew $version: (_validate-version version)
    set -euo pipefail

    version="{{version}}"
    brew tap nekonata-team/tap

    brew bump-cask-pr \
        --version "$version" \
        --no-fork \
        --no-browse \
        nekonata-team/tap/den-browser

    gh pr merge "bump-den-browser-${version}" \
        --repo nekonata-team/homebrew-tap \
        --auto \
        --rebase

# Bump version and build a release candidate.
prepare $version: (_validate-version version) _require-clean (set-version version) verify (candidate version) (appcast version)

# Commit and publish a verified candidate to GitHub and Homebrew.
[confirm("Publish verified release candidate?")]
publish $version: (_validate-version version) _require-main _commit-version-if-needed
    [[ -z "$(git status --porcelain)" ]]
    just --yes release github "$version"
    git push origin main
    just --yes release homebrew "$version"

# Prepare and publish without manual candidate verification.
[confirm("Prepare and publish release without manual verification?")]
ship $version: (_validate-version version) _require-main (prepare version)
    just --yes release publish "$version"
