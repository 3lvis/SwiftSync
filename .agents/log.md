# Transcript Delta

## 2026-02-27 — Test fix: unrelated-type reload assertion

Command:
```bash
swift test --filter SyncQueryPublisherTests/testPublisherDoesNotReloadForUnrelatedTypeChange
```

Output (trimmed):
```
XCTAssertEqual failed: ("1") is not equal to ("0")
```

Notes:
- Test assumed `PubUser` changes would not trigger a `PubTask` publisher reload
- Wrong: `@Syncable` on `PubTask` generates `syncDefaultRefreshModelTypes` that includes `PubUser` because of the `assignee: PubUser?` relationship — this is correct and intentional behavior
- Fix: introduced `PubUnrelatedTag` (no relationship to `PubTask`) and synced that instead; reloadCount correctly stays 0

---

## 2026-02-27 — Build fix: Section enum Sendable error

Command:
```bash
xcodebuild -workspace SwiftSync.xcworkspace -scheme Demo -destination "generic/platform=iOS" build
```

Output (trimmed):
```
error: main actor-isolated conformance of 'UserTasksViewController.Section' to 'Hashable'
cannot satisfy conformance requirement for a 'Sendable' type parameter 'SectionIdentifierType'
```

Notes:
- Tried: inner `private enum Section` inside the class — same error
- Tried: top-level `private enum UserTasksSection: Hashable, Sendable` — same error (SwiftData import causes main actor isolation inference on the whole file)
- Fix: use `String` as `UITableViewDiffableDataSource` section identifier; section key is `"tasks"`

---

## 2026-02-27 — Final state

Command:
```bash
swift test
```

Output (trimmed):
```
Executed 104 tests, with 0 failures (0 unexpected)
```

Command:
```bash
xcodebuild ... build
```

Output:
```
** BUILD SUCCEEDED **
```

Command:
```bash
git push -u origin feature/uikit-support
```

Output:
```
* [new branch] feature/uikit-support -> feature/uikit-support
```
