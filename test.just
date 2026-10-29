set shell := ["zsh", "-cu"]
set positional-arguments := true

project := "Den Browser/Den Browser.xcodeproj"
unit_test_scheme := "Den Browser UnitTests"
ui_test_scheme := "Den Browser UITests"
derived_data := ".derived-data"
ui_test_derived_data := ".derived-data-ui"
unit_test_result := derived_data + "/TestResults.xcresult"
ui_test_result := ui_test_derived_data + "/TestResults.xcresult"

# Prevent ast-grep (terminal-light) from leaking OSC 11 background color queries.
ast_grep := 'COLORFGBG="15;0" ast-grep'

# Run unit tests without code signing.
[default]
unit: packages
    @rm -rf "{{unit_test_result}}"
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{unit_test_scheme}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{derived_data}}' -resultBundlePath '{{unit_test_result}}' -only-testing:'Den BrowserTests' -parallel-testing-enabled YES CODE_SIGNING_ALLOWED=NO" || { echo "✗ Unit tests failed."; echo '  Inspect: just test results'; exit 1; }
    echo "✓ Unit tests passed"

# Run deterministic macOS UI interaction tests. Pass a target, then an optional configuration (e.g. just test ui Den_BrowserUIPerformanceTests Release).
ui target="Den_BrowserUITests" configuration="Debug":
    @rm -rf "{{ui_test_result}}"
    @rtk test "xcodebuild test -project '{{project}}' -scheme '{{ui_test_scheme}}' -configuration '{{configuration}}' -destination 'platform=macOS,arch=arm64' -derivedDataPath '{{ui_test_derived_data}}' -resultBundlePath '{{ui_test_result}}' -only-testing:'Den BrowserUITests/{{target}}'" || { echo "✗ UI tests failed."; echo '  Inspect: just test results .derived-data-ui/TestResults.xcresult'; exit 1; }
    echo "✓ UI tests passed"

# Show a test result summary. Pass another result bundle path as the first argument.
results result_path=unit_test_result:
    @test -d "{{result_path}}"
    xcrun xcresulttool get test-results summary --path "{{result_path}}"

# Test architecture rule definitions against their fixtures.
architecture:
    @{{ast_grep}} test --config sgconfig.yml --skip-snapshot-tests

# Test or build all local packages, treating compiler warnings as errors.
packages:
    @rtk test "swift test --package-path Packages/DenApplication -Xswiftc -warnings-as-errors"
    @rtk test "swift test --package-path Packages/DenModels -Xswiftc -warnings-as-errors"
    @rtk test "swift test --package-path Packages/DenInfrastructure -Xswiftc -warnings-as-errors"
    @rtk test "swift test --package-path Packages/DenIPCProtocol -Xswiftc -warnings-as-errors"
    @rtk test "swift build --package-path Packages/DenViews -Xswiftc -warnings-as-errors"
    @rtk test "swift build --package-path Packages/DenDemo -Xswiftc -warnings-as-errors"
    @echo "✓ Package checks passed"
