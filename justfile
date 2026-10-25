set shell := ["zsh", "-cu"]
set positional-arguments := true

project := "Den Browser/Den Browser.xcodeproj"
scheme := "Den Browser"
derived_data := ".derived-data"
ui_test_derived_data := ".derived-data-ui"
export SPARKLE_TOOLS := derived_data + "/SourcePackages/artifacts/sparkle/Sparkle/bin"
swift_format := "xcrun swift-format"
# Prevent ast-grep (terminal-light) from leaking OSC 11 background color queries.
ast_grep := 'COLORFGBG="15;0" ast-grep'
swift_sources := "Den Browser"
domain_sources := "Packages/DenDomain/Sources"
ipc_protocol_sources := "Packages/DenIPCProtocol/Sources"
application_sources := "Packages/DenApplication/Sources"
models_sources := "Packages/DenModels/Sources"
views_sources := "Packages/DenViews/Sources"
infrastructure_sources := "Packages/DenInfrastructure/Sources"
demo_sources := "Packages/DenDemo/Sources"

# Web works.
mod web

# Prepare and publish signed releases.
mod release

# Test automation.
mod test

# Demo automation and video generation.
mod demo

# Format all Swift sources in place.
[group("quality")]
format:
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{swift_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{domain_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{ipc_protocol_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{application_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{models_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{views_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{infrastructure_sources}}"
    @{{swift_format}} format --in-place --recursive --parallel --configuration .swift-format "{{demo_sources}}"

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
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{ipc_protocol_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{application_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{models_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{views_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{infrastructure_sources}}"
    @{{swift_format}} lint --strict --recursive --parallel --configuration .swift-format "{{demo_sources}}"

# Fail on Swift style and safety findings.
[group("quality")]
lint: architecture-check format-check
    @swiftlint lint --quiet --strict

# Check Swift layer import rules against source files.
[group("quality")]
architecture-check:
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

# Run lint, TypeScript checks, and unit tests.
[group("quality")]
check: lint embedded-js-typecheck
    just test
