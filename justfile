set shell := ["zsh", "-cu"]

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
ui_test_derived_data := ".derived-data-ui"
export SPARKLE_TOOLS := derived_data + "/SourcePackages/artifacts/sparkle/Sparkle/bin"
swift_format := "xcrun swift-format"
swift_sources := "Den Browser"

# Web works.
mod web

# Prepare and publish signed releases.
mod release

# Format all Swift sources in place.
[group("quality")]
format:
    {{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{swift_sources}}"

# Format staged Swift sources in place.
[group("quality")]
[positional-arguments]
format-staged +files:
    {{swift_format}} format --in-place --parallel --configuration .swift-format "$@"

# Fail on Swift style and safety findings.
[group("quality")]
lint:
    {{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{swift_sources}}"
    swiftlint lint --strict

# Build macOS app without code signing.
[group("build")]
build:
    rtk xcodebuild build -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS,arch=arm64' -derivedDataPath "{{derived_data}}" CODE_SIGNING_ALLOWED=NO

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
    rm -rf "{{derived_data}}" "{{ui_test_derived_data}}"

[group("development")]
precommit:
    lefthook run pre-commit

[group("development")]
prepush:
    lefthook run pre-push

# Run unit tests without code signing.
[group("test")]
test:
    rtk test "xcodebuild test -project '{{project}}' -scheme '{{scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{derived_data}}' -only-testing:'Den BrowserTests' -parallel-testing-enabled YES CODE_SIGNING_ALLOWED=NO" || { echo "✗ Unit tests failed."; echo '  Inspect: xcrun xcresulttool get test-results summary --path "$(ls -td .derived-data/Logs/Test/*.xcresult | head -n 1)"'; exit 1; }
    echo "✓ Unit tests passed"

# Run deterministic macOS UI interaction tests. Pass a target to run a specific class or case (e.g. just ui-test Den_BrowserUITests/testNewBoardIsCenteredAfterCreation).
[group("test")]
ui-test target="Den_BrowserUITests":
    rtk test "xcodebuild test -project '{{project}}' -scheme '{{scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{ui_test_derived_data}}' -only-testing:'Den BrowserUITests/{{target}}' CODE_SIGNING_ALLOWED=NO" || { echo "✗ UI tests failed."; echo '  Inspect: xcrun xcresulttool get test-results summary --path "$(ls -td .derived-data-ui/Logs/Test/*.xcresult | head -n 1)"'; exit 1; }
    echo "✓ UI tests passed"

# Run lint and unit tests.
[group("test")]
check: lint test
