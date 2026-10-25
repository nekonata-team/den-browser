set shell := ["zsh", "-cu"]
set positional-arguments := true

# Run demo scenario in isolated Demo Mode without recording.
[default]
run scenario="promotional":
    just build
    just demo _run "{{scenario}}"

# Record demo video using OpenScreen, then compress for web delivery.
pv scenario="promotional" output="demo.mp4":
    just build
    just demo _record "{{scenario}}" "{{output}}"

# Record all demo videos for the web showcase.
pv-all:
    just build
    just demo _record promotional web/public/videos/preview.mp4
    just demo _record agent-verify web/public/videos/agent-verify.mp4
    just demo _record agent-desk web/public/videos/agent-desk.mp4
    just demo _record agent-show-me web/public/videos/agent-show-me.mp4

[private]
_run scenario:
    swift run --package-path Packages/DenDemo den-demo --scenario "{{scenario}}"

[private]
_record scenario output:
    swift run --package-path Packages/DenDemo den-demo --scenario "{{scenario}}" --record "{{output}}" --overwrite
    just demo compress "{{output}}"

# Generate a WebP poster frame from a video for web delivery.
poster video="web/public/videos/preview.mp4" output="web/public/videos/poster.webp":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{video}}" ]; then
        echo "Error: Video not found: {{video}}" >&2
        exit 1
    fi
    echo "Generating poster {{output}} from {{video}}…"
    ffmpeg -y -ss 00:00:01 -i "{{video}}" -vframes 1 -vcodec libwebp -q:v 80 "{{output}}"
    echo "✓ Generated {{output}}"

# Compress video (MP4) for web delivery.
compress target:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{target}}" ]; then
        echo "Error: File not found: {{target}}" >&2
        exit 1
    fi
    dir=$(dirname "{{target}}")
    base=$(basename "{{target}}")
    tmp="$dir/.compress-$base"
    echo "Compressing video {{target}}…"
    ffmpeg -y -i "{{target}}" -vcodec libx264 -crf 22 -preset medium -an -movflags +faststart "$tmp"
    mv "$tmp" "{{target}}"
    echo "✓ Compressed {{target}}"
