# Transcript Delta

## 2026-02-27 iOS CI failure root cause

Command:

```bash
gh run view 22474927008 --log-failed
```

Output (trimmed):

```text
xcodebuild: error: The workspace named "SwiftSync" does not contain a scheme named "SwiftSync-Package".
Process completed with exit code 65.
```

Notes:

- `SwiftSync.xcworkspace` exists at repo root; it only contains schemes `Demo` and `DemoBackend`
- xcodebuild auto-discovers the workspace even without `-workspace` flag
- `SwiftSync-Package` is an SPM-generated scheme that only appears when opening a bare package (no workspace)
- Fix: replace xcodebuild invocation with `swift test` targeting the iOS simulator SDK

## 2026-02-27 Workspace scheme list

Command:

```bash
xcodebuild -workspace SwiftSync.xcworkspace -list
```

Output (trimmed):

```text
Schemes:
    Demo
    DemoBackend
```

Notes:

- No SwiftSync-Package scheme — confirms root cause
