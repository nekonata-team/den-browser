set shell := ["zsh", "-cu"]

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
ui_derived_data := ".derived-data-ui"
swift_format := "xcrun swift-format"
swift_sources := "Den Browser"

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

# Run unit tests without code signing.
[group("test")]
test:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" -only-testing:'Den BrowserTests' CODE_SIGNING_ALLOWED=NO

# Run deterministic macOS UI interaction tests.
[group("test")]
ui-test:
    xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{ui_derived_data}}" -only-testing:'Den BrowserUITests'

# Build then run unit tests.
[group("test")]
check: lint build test
