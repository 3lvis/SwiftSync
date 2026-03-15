#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$ROOT_DIR/SwiftSync.xcworkspace"
SCHEME="Demo"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-ui-tests}"
SIMULATOR_UDID="${SIMULATOR_UDID:-A40EFA3C-8E6A-40B2-9FF1-C4C1944B3CC7}"
ONLY_TESTING="${1:-}"
FORCE_BUILD="${FORCE_BUILD:-0}"

if [[ -z "$ONLY_TESTING" ]]; then
  echo "usage: scripts/run_ui_test.sh DemoUITests/DemoUITests/testName"
  exit 64
fi

DESTINATION="id=$SIMULATOR_UDID"
XCTESTRUN_PATH="$(find "$DERIVED_DATA_PATH/Build/Products" -name '*.xctestrun' -print -quit 2>/dev/null || true)"

echo "Using simulator UDID: $SIMULATOR_UDID"
echo "Using derived data path: $DERIVED_DATA_PATH"
echo "Targeted test: $ONLY_TESTING"

mkdir -p "$DERIVED_DATA_PATH"

echo "==> Booting simulator"
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

if [[ "$FORCE_BUILD" == "1" || -z "$XCTESTRUN_PATH" ]]; then
  echo "==> Building for testing"
  xcodebuild build-for-testing \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY=''
else
  echo "==> Reusing existing build-for-testing products"
fi

run_test() {
  xcodebuild test-without-building \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -only-testing:"$ONLY_TESTING" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY=''
}

echo "==> Running targeted UI test"
if run_test; then
  exit 0
fi

echo "First launch failed; rebooting simulator and retrying once"
xcrun simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
run_test
