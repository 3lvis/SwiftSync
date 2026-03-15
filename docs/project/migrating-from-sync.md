# Migrating From Sync

Read this if you used the old Core Data library `Sync` and are evaluating SwiftSync.

## First Principle

SwiftSync is the successor to `Sync` in spirit, not a drop-in upgrade.

The old project was:
- Core Data based
- Objective-C/Swift interoperability era
- built around `DataStack`, entity names, and Core Data model conventions

SwiftSync is:
- SwiftData based
- Swift macro driven
- built around `@Syncable`, `SyncContainer`, and reactive local reads

## What Stays The Same

The core value proposition is still familiar:
- convention-first JSON mapping
- relationship syncing
- insert/update/delete diffing
- exporting local models back to JSON

If you liked `Sync` because it removed repetitive mapping and syncing code, that same motivation is what SwiftSync is built for.

## What Changes

You should expect real migration work in these areas:

1. Persistence layer
   `Sync` targeted Core Data. SwiftSync targets SwiftData.

2. Model definition
   `Sync` relied on Core Data models and metadata.
   SwiftSync uses Swift types with `@Model` and `@Syncable`.

3. API surface
   `DataStack.sync(...)` style calls become `SyncContainer.sync(...)` and related APIs.

4. UI integration
   SwiftSync is designed around reactive local reads with `@SyncQuery`, `@SyncModel`, `SyncQueryPublisher`, and `SyncModelPublisher`.

5. Contract strictness
   SwiftSync is explicit about payload semantics:
   - missing key = ignore
   - explicit `null` = clear

## Recommended Migration Approach

Do not try to "upgrade in place" line by line.

Instead:

1. Migrate one feature or resource at a time.
2. Recreate the model in SwiftData + `@Syncable`.
3. Align the backend payload contract with the documented SwiftSync conventions.
4. Replace imperative mutation callbacks with reactive local reads where possible.

## Read Next

- [README.md](../../README.md)
- [backend-contract.md](backend-contract.md)
- [reactive-reads.md](reactive-reads.md)
- [property-mapping-contract.md](property-mapping-contract.md)
