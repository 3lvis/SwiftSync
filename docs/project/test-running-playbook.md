# Test-Running Playbook

This document defines the standard way to run tests in this repo.

## Rules

- Run commands sequentially.
- For library and backend work, start with `swift test`.
- For `Demo/Demo/**` changes, build the demo app before finishing.
- For UI-test debugging, use the local loop script and run one UI test at a time.

## Default commands by change type

### Swift package and backend changes

Use:

```bash
swift test
```

Run this for changes in:

- `SwiftSync/**`
- `DemoBackend/**`
- `DemoCore/**` when the change does not require an Xcode-only surface

### Demo app UI or behavior changes

Always finish with:

```bash
xcodebuild build \
  -workspace SwiftSync.xcworkspace \
  -scheme Demo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=''
```

Run this for changes in:

- `Demo/Demo/**`
- `Demo/DemoUITests/**`

The Demo UI suite is intentionally capped at core end-to-end journeys.
Prefer adding coverage in lower-level tests unless a new user-visible journey truly requires UI automation.

## UI test debugging loop

Do not run full `xcodebuild test` repeatedly when fixing UI tests.

Run focused UI tests through:

```bash
./scripts/run_ui_test.sh DemoUITests/DemoUITests/testProjectAndTaskDetailShowSeededContent
```

This script is the standard local UI-test loop. It:

- pins one installed simulator UDID
- boots the simulator and waits for boot completion
- uses one shared derived-data path
- disables parallel testing
- reuses `build-for-testing` products across targeted runs
- retries once after reboot if the runner fails to launch

## Underlying commands

### Build for testing

```bash
xcodebuild build-for-testing \
  -workspace SwiftSync.xcworkspace \
  -scheme Demo \
  -destination 'id=<installed-simulator-udid>' \
  -parallel-testing-enabled NO \
  -derivedDataPath .build/xcode-ui-tests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=''
```

### Run one UI test without rebuilding

```bash
xcodebuild test-without-building \
  -workspace SwiftSync.xcworkspace \
  -scheme Demo \
  -destination 'id=<installed-simulator-udid>' \
  -parallel-testing-enabled NO \
  -derivedDataPath .build/xcode-ui-tests \
  -only-testing:DemoUITests/DemoUITests/testProjectAndTaskDetailShowSeededContent \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=''
```

Replace the final test identifier with the exact failing test name.

## Simulator preflight

Before `test-without-building`, boot the exact simulator and wait for it to finish booting.

Use:

```bash
xcrun simctl boot <installed-simulator-udid> || true
xcrun simctl bootstatus <installed-simulator-udid> -b
```

Do not use device names. Use an installed simulator UDID so reruns stay on the same device.

## Parallel testing

Disable parallel testing for focused UI runs.

Use:

```bash
-parallel-testing-enabled NO
```

## Derived data reuse

Use one explicit derived-data path for the focused UI-test loop:

```bash
-derivedDataPath .build/xcode-ui-tests
```

Keep `build-for-testing` and `test-without-building` on the same path.

## Wait policy

Use the smallest wait that proves the contract.

- Start with `0.5` or `1` second.
- Increase only when the failing surface is genuinely asynchronous.
- Do not add broad sleeps to hide selector or accessibility bugs.

Use:

- `waitForExistence(timeout:)`
- `waitForNonExistence(timeout:)`

Do not use:

- arbitrary long waits
- sleeps
- retry loops that hide deterministic failures

## Assertion policy for UI tests

Assert the most stable user-meaningful surface.

- Prefer accessibility identifiers over positional queries.
- Do not assume XCTest will always expose a view as the same element type.
- If an identified element is sometimes surfaced as `Other` and sometimes as `StaticText`, query by identifier across `.any` instead of binding the test to one XCUI type.

## Standard execution order

When fixing a UI bug or broken UI test, use this order:

1. Pick one installed simulator UDID and keep using it for the whole session.
2. Boot that simulator and wait for boot completion.
3. Run `build-for-testing` once with `-parallel-testing-enabled NO` and `-derivedDataPath .build/xcode-ui-tests`.
4. Run one failing UI test with `test-without-building` on the same simulator UDID and derived-data path.
5. Fix the bug.
6. Re-run that same UI test with `test-without-building`.
7. Run the next failing UI test with `test-without-building`.
8. If the runner fails to launch, retry the same targeted run once after rebooting the simulator.
9. After the focused fixes are done, run the required demo build:

```bash
xcodebuild build \
  -workspace SwiftSync.xcworkspace \
  -scheme Demo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=''
```

Follow this playbook by default.
