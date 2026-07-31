set shell := ["zsh", "-cu"]

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
swift_format := "xcrun swift-format"
swift_sources := "Den Browser"

# Prepare and publish signed releases.
mod release

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
    rtk xcodebuild build -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" CODE_SIGNING_ALLOWED=NO

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
    rtk xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" -only-testing:'Den BrowserTests' CODE_SIGNING_ALLOWED=NO

# Run deterministic macOS UI interaction tests. Pass a target to run a specific class or case (e.g. just ui-test Den_BrowserUITests/testNewBoardIsCenteredAfterCreation).
[group("test")]
ui-test target="":
    rtk xcodebuild test -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" -enableCodeCoverage NO -only-testing:"Den BrowserUITests{{ if target == "" { "" } else { "/" + target } }}"

# Build then run unit tests.
[group("test")]
check: lint build test
