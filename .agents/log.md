# Transcript Delta

## 2026-02-28 demo/export-create-body

Command:
```bash
swift test --package-path DemoBackend
```

Output (trimmed):
```
Executed 8 tests, with 0 failures (0 unexpected) in 0.037 seconds
```

Notes:
- All 8 DemoBackendTests pass including 3 new createTask(body:) tests

---

Command:
```bash
swift test --package-path SwiftSync
```

Output (trimmed):
```
Test run with 30 tests in 4 suites passed after 0.007 seconds.
```

Notes:
- No regressions in SwiftSync library tests

---

Command:
```bash
xcodebuild build -workspace SwiftSync.xcworkspace -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Output:
```
** BUILD SUCCEEDED **
```
