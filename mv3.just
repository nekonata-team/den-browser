set shell := ["zsh", "-cu"]

repository := "uBlockOrigin/uBOL-home"
destination := "Den Browser/Den Browser/Resources/WebExtensions/uBOLite.safari.zip"

# Validate an MV3 archive and print its version.
[script]
_inspect-mv3-archive archive:
    set -euo pipefail

    unzip -t "{{archive}}" >/dev/null
    unzip -p "{{archive}}" manifest.json \
        | jq -er 'select(.manifest_version == 3) | .version'

# Download the latest uBOL Safari archive.
[script]
update-ubolite:
    set -euo pipefail

    temporary="$(mktemp "{{destination}}.XXXXXX")"
    trap 'rm -f "$temporary"' EXIT

    printf '%s\n' 'Downloading the latest uBOL Safari archive...'
    gh release download \
        --repo "{{repository}}" \
        --pattern 'uBOLite_*.safari.zip' \
        --output "$temporary" \
        --clobber
    version="$(just --quiet mv3 _inspect-mv3-archive "$temporary")"
    new_sha256="$(shasum -a 256 "$temporary" | awk '{print $1}')"

    if [[ -f "{{destination}}" ]]; then
        old_sha256="$(shasum -a 256 "{{destination}}" | awk '{print $1}')"
        if cmp -s "$temporary" "{{destination}}"; then
            printf 'uBOLite %s: already up to date\n' "$version"
            printf 'SHA-256: %s\n' "$new_sha256"
            exit 0
        fi
    else
        old_sha256='(none)'
    fi

    mv "$temporary" "{{destination}}"
    trap - EXIT
    printf 'uBOLite %s: updated\n' "$version"
    printf 'SHA-256: %s -> %s\n' "$old_sha256" "$new_sha256"
    printf 'Destination: %s\n' "{{destination}}"
