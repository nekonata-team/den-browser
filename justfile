set shell := ["zsh", "-cu"]
set positional-arguments := true

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
unit_test_scheme := "Den Browser UnitTests"
ui_test_scheme := "Den Browser UITests"
derived_data := ".derived-data"
ui_test_derived_data := ".derived-data-ui"
unit_test_result := derived_data + "/TestResults.xcresult"
ui_test_result := ui_test_derived_data + "/TestResults.xcresult"
export SPARKLE_TOOLS := derived_data + "/SourcePackages/artifacts/sparkle/Sparkle/bin"
swift_format := "xcrun swift-format"
# Prevent ast-grep (terminal-light) from leaking OSC 11 background color queries.
ast_grep := 'COLORFGBG="15;0" ast-grep'
swift_sources := "Den Browser"
domain_sources := "Packages/DenDomain/Sources"
design_sources := "Packages/DenDesign/Sources"
ipc_protocol_sources := "Packages/DenIPCProtocol/Sources"
application_sources := "Packages/DenApplication/Sources"
presentation_sources := "Packages/DenPresentationModels/Sources"
infrastructure_sources := "Packages/DenInfrastructure/Sources"

# Web works.
mod web

# Prepare and publish signed releases.
mod release

# Format all Swift sources in place.
[group("quality")]
format:
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{swift_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{domain_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{design_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{ipc_protocol_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{application_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{presentation_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{infrastructure_sources}}"

# Format staged Swift sources in place.
[group("quality")]
[positional-arguments]
format-staged +files:
    {{swift_format}} format --in-place --parallel --configuration .swift-format "$@"

# Check Swift formatting without modifying files.
[group("quality")]
format-check:
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{swift_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{domain_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{design_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{ipc_protocol_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{application_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{presentation_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{infrastructure_sources}}"

# Fail on Swift style and safety findings.
[group("quality")]
lint: architecture-check format-check
    @swiftlint lint --quiet --strict

# Check Swift layer import rules and their fixtures.
[group("quality")]
architecture-check:
    @{{ast_grep}} test --config sgconfig.yml --skip-snapshot-tests
    @{{ast_grep}} scan --config sgconfig.yml

# Build macOS app with development signing.
[group("build")]
build:
    @rtk xcodebuild build -project "{{project}}" -scheme "{{scheme}}" -destination 'platform=macOS,arch=arm64' -derivedDataPath "{{derived_data}}"

# Type-check embedded JavaScript sources.
[group("quality")]
embedded-js-typecheck:
    @pnpm --dir scripts/embedded-js typecheck

# Bind SourceKit-LSP to this Xcode project.
[group("development")]
lsp-config:
    xcode-build-server config -project "{{project}}" -scheme "{{scheme}}"

# Build and launch the application locally.
[group("development")]
run: build
    open -n "{{derived_data}}/Build/Products/Debug/Den Browser.app"

# Build and launch the application locally in a Private Den.
[group("development")]
run-private: build
    open -n "{{derived_data}}/Build/Products/Debug/Den Browser.app" --args --private-den

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
    @"{{derived_data}}/Build/Products/Debug/Den Browser.app/Contents/MacOS/den" "$@"

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
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{unit_test_scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{derived_data}}' -resultBundlePath '{{unit_test_result}}' -only-testing:'Den BrowserTests' -parallel-testing-enabled YES CODE_SIGNING_ALLOWED=NO" || { echo "✗ Unit tests failed."; echo '  Inspect: just test-results'; exit 1; }
    echo "✓ Unit tests passed"

# Run deterministic macOS UI interaction tests. Pass target or configuration (e.g. just ui-test configuration=Release).
[group("test")]
ui-test target="Den_BrowserUITests" configuration="Debug":
    @rm -rf "{{ui_test_result}}"
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{ui_test_scheme}}' -configuration '{{configuration}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{ui_test_derived_data}}' -resultBundlePath '{{ui_test_result}}' -only-testing:'Den BrowserUITests/{{target}}'" || { echo "✗ UI tests failed."; echo '  Inspect: just test-results .derived-data-ui/TestResults.xcresult'; exit 1; }
    echo "✓ UI tests passed"

# Show a test result summary. Pass another result bundle path as the first argument.
[group("test")]
test-results result_path=unit_test_result:
    @test -d "{{result_path}}"
    xcrun xcresulttool get test-results summary --path "{{result_path}}"

# Run lint, TypeScript checks, and unit tests.
[group("test")]
check: lint embedded-js-typecheck test
