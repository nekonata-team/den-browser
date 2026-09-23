set shell := ["zsh", "-cu"]
set positional-arguments := true

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
ui_test_derived_data := ".derived-data-ui"
unit_test_result := derived_data + "/TestResults.xcresult"
ui_test_result := ui_test_derived_data + "/TestResults.xcresult"
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
    swiftlint lint --quiet --strict

# Build macOS app with development signing.
[group("build")]
build:
    @rtk xcodebuild build -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS,arch=arm64' -derivedDataPath "{{derived_data}}"

# Type-check embedded JavaScript sources.
[group("quality")]
embedded-js-typecheck:
    pnpm --dir scripts/embedded-js typecheck

# Bind SourceKit-LSP to this Xcode project.
[group("development")]
lsp-config:
    xcode-build-server config -project "{{project}}" -scheme "{{scheme}}"

# Build and launch the application locally.
[group("development")]
run: build
    open -n "{{derived_data}}/Build/Products/Debug/Den Browser.app"

# Quit Den Browser.
[group("development")]
quit:
    osascript -e 'tell application "Den Browser" to quit'

# Quit Den Browser, then build and launch it again.
[group("development")]
restart: quit && run

# Run the bundled den CLI.
[group("development")]
den *args:
    "{{derived_data}}/Build/Products/Debug/Den Browser.app/Contents/MacOS/den" "$@"

# Benchmark startup and idle resource usage.
[group("development")]
benchmark scenario *args: build
    swift scripts/measure.swift --scenario "{{scenario}}" {{args}}

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
    @rm -rf "{{unit_test_result}}"
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{derived_data}}' -resultBundlePath '{{unit_test_result}}' -only-testing:'Den BrowserTests' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO" || { echo "✗ Unit tests failed."; echo '  Inspect: just test-results'; exit 1; }
    echo "✓ Unit tests passed"

# Run deterministic macOS UI interaction tests. Pass a target to run a specific class or case (e.g. just ui-test Den_BrowserUITests/testNewBoardIsCenteredAfterCreation).
[group("test")]
ui-test target="Den_BrowserUITests":
    @rm -rf "{{ui_test_result}}"
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{ui_test_derived_data}}' -resultBundlePath '{{ui_test_result}}' -only-testing:'Den BrowserUITests/{{target}}'" || { echo "✗ UI tests failed."; echo '  Inspect: just test-results .derived-data-ui/TestResults.xcresult'; exit 1; }
    echo "✓ UI tests passed"

# Show a test result summary. Pass another result bundle path as the first argument.
[group("test")]
test-results result_path=unit_test_result:
    @test -d "{{result_path}}"
    xcrun xcresulttool get test-results summary --path "{{result_path}}"

# Run lint, TypeScript checks, and unit tests.
[group("test")]
check: lint embedded-js-typecheck test
