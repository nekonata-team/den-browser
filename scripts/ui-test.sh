#!/usr/bin/env bash
set -euo pipefail

# xcodebuild continues a test suite after failures; run each UI test separately
# so release preparation stops at the first failure.
project="Den Browser/Den Browser.xcodeproj"
scheme="Den Browser"
derived_data=".derived-data"
target="${1:-}"

run_test() {
    rtk xcodebuild test \
      -project "$project" \
      -scheme "$scheme" \
      -destination 'platform=macOS' \
      -derivedDataPath "$derived_data" \
      -enableCodeCoverage NO \
      -only-testing:"$1"
}

if [[ -n "$target" ]]; then
    run_test "Den BrowserUITests/$target"
    exit
fi

tmp_dir="$(mktemp -d)"
enumeration="$tmp_dir/tests.json"
trap 'rm -rf "$tmp_dir"' EXIT

rtk xcodebuild test \
  -project "$project" \
  -scheme "$scheme" \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  -enumerate-tests \
  -test-enumeration-format json \
  -test-enumeration-output-path "$enumeration" >/dev/null

jq -r '
  def tests($path):
    . as $node |
    if $node.kind == "test" then
      (($path + [$node.name | sub("\\(\\)$"; "")]) | join("/"))
    else
      $node.children[]? | tests($path + [$node.name])
    end;

  .values[] |
  .children[]? |
  select(.kind == "target" and .name == "Den BrowserUITests") |
  tests([])
' "$enumeration" |
while IFS= read -r test_id; do
    run_test "$test_id"
done
