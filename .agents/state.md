# State Capsule

## Plan

- [x] Bump platforms to iOS 18 / macOS 15 in all three Package.swift (root, DemoCore, DemoBackend)
- [x] Confirm swift-tools 6.2 + swiftLanguageModes [.v6] unchanged everywhere (already correct)
- [x] Run `swift test` on root (48 swift-testing + XCTest green), DemoCore (21), DemoBackend (21)
- [x] Build Demo app (iOS Simulator) — BUILD SUCCEEDED
- [x] Remove completed Phase 0 items from world-class-roadmap.md
- [ ] Commit; push; open draft PR

## Last known state

green — all three packages test-pass and Demo app builds against the bumped manifests

## Decisions (don't revisit)

- Platforms: iOS 18 + macOS 15 only (no tvOS/watchOS) — matches Networking's Swift version + iOS 18 floor.
- Demo app project already at IPHONEOS_DEPLOYMENT_TARGET 26.2, above the lib floor — no change needed.
- Build-config change, no behavior delta → verified via tests/build staying green, not red-first TDD.
- DemoCore tests + Demo app build cannot run inside this worktree: SPM derives the parent
  package name from the directory (`SwiftSync-chore--platform-bump-ios18` != `SwiftSync`), so
  `.package(path: "../")` fails to resolve `package: "SwiftSync"`. Verified by rsync-copying the
  tree into a real `SwiftSync`-named dir and running there. CI checks out as `SwiftSync`, so this
  is a worktree-only artifact, not a defect.

## Files touched

- Package.swift
- DemoCore/Package.swift
- DemoBackend/Package.swift
- docs/planning/world-class-roadmap.md
</content>
