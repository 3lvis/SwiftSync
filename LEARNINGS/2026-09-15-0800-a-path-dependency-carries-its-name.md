**An unnamed `.package(path:)` takes its identity from the directory name, so a multi-package repo stops
resolving the moment it is checked out under any other name.** `DemoCore` depended on the root package as
`.package(path: "../")`, which SwiftPM reads as a package called `SwiftSync` because that is what the
directory is called. In a git worktree at `SwiftSync-chore--xcode-27-toolchain` the same manifest fails
with `unknown package 'SwiftSync' in dependencies of target 'DemoCore'; valid packages are:
'SwiftSync-chore--xcode-27-toolchain'` — and it fails for `swift package resolve`, for
`xcodebuild -list`, and so for every scheme in the workspace, which makes the whole repo untestable from a
worktree. `.package(name: "SwiftSync", path: "../")` takes the identity from the manifest instead and the
directory name stops mattering. Name every `path:` dependency the day it is added.
*— Elvis, 2026-09-15 08:00*
