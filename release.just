set shell := ["zsh", "-cu"]

fastlane := "bundle exec fastlane"

_validate-version $version:
    @[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { printf '%s\n' 'usage: version must be X.Y.Z' >&2; exit 1; }

_validate-tag $tag:
    @[[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || { printf '%s\n' 'usage: tag must be vX.Y.Z' >&2; exit 1; }

_require-main:
    @[[ "$(git branch --show-current)" == main ]] || { printf '%s\n' 'release must run on main' >&2; exit 1; }

_require-clean:
    @[[ -z "$(git status --porcelain)" ]] || { printf '%s\n' 'working tree has uncommitted changes' >&2; exit 1; }

[script]
_commit-version-if-needed:
    set -euo pipefail

    git add "Den Browser/Den Browser.xcodeproj/project.pbxproj"

    if git diff --cached --quiet -- "Den Browser/Den Browser.xcodeproj/project.pbxproj"; then
        printf '%s\n' 'version unchanged; skipping commit'
    else
        git commit -m "bump: バージョンを更新" -- "Den Browser/Den Browser.xcodeproj/project.pbxproj"
    fi

# Set version and auto-increment build number.
set-version version: (_validate-version version)
    {{fastlane}} bump_version version:{{version}}

# Build, sign, notarize, and package a release candidate.
[confirm("Build release candidate?")]
candidate tag: (_validate-tag tag)
    {{fastlane}} release_candidate tag:{{tag}}

# Publish a tested release candidate to GitHub.
[confirm("Publish candidate to GitHub?")]
[script]
github $tag: (_validate-tag tag)
    set -euo pipefail

    [[ -z "$(git status --porcelain)" ]] || {
        printf '%s\n' "working tree has uncommitted changes" >&2
        exit 1
    }

    version="${tag#v}"
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
[confirm("Prepare release candidate?")]
prepare $version: (_validate-version version) _require-clean
    just release set-version "$version"
    just --yes release candidate "v${version}"

# Commit and publish a verified candidate to GitHub and Homebrew.
[confirm("Publish verified release candidate?")]
publish $version: (_validate-version version) _require-main
    just release _commit-version-if-needed
    [[ -z "$(git status --porcelain)" ]]
    git push origin main
    just --yes release github "v${version}"
    just --yes release homebrew "$version"
