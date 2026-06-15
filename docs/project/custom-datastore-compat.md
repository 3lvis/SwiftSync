# Custom `DataStore` Compatibility

## Short answer

SwiftSync is **store-agnostic**. It works with any `ModelContainer` — the default SQLite store
or a custom SwiftData `DataStore` — as long as the store honours standard SwiftData semantics
(below). SwiftSync never touches `DataStoreConfiguration` or any store internals.

## What SwiftSync actually depends on

Determined by auditing SwiftSync's SwiftData API surface (`ModelContext` ×40, `FetchDescriptor`
×18, `PersistentIdentifier` ×17, `ModelContext.didSave` ×7, plus `Schema` / `ModelContainer` /
`ModelConfiguration`). A backing store must support:

1. **`ModelContext.fetch(_:)` with `FetchDescriptor`** — `#Predicate` filtering and `sortBy`.
   Used for identity lookups, parent-scope queries, and `@SyncQuery` reads.
2. **`insert` / `save` / `delete`** and **relationship persistence + faulting** (to-one and
   to-many) — the upsert and relationship-resolution machinery.
3. **`ModelContext.didSave` notifications** carrying inserted/updated/deleted
   `PersistentIdentifier`s — the linchpin for reactive reads. **This is the one to watch:** if a
   custom store does not post `didSave`, inbound sync still works, but `@SyncQuery` / `@SyncModel`
   and the publishers won't auto-refresh (you'd have to refresh manually). See
   [ios-dirty-tracking-gap.md](ios-dirty-tracking-gap.md) for a related `didSave` nuance.
4. **`ModelContainer(for:configurations:)`** initialisation. NSExceptions thrown during init are
   caught by SwiftSync's ObjC bridge regardless of store.

## Caveats

- Unique-constraint **upsert** behaviour is the store's, not SwiftSync's. The uniqueness rule in
  [property-mapping-contract.md](property-mapping-contract.md) (uniqueness only on the sync
  identity) applies on any store.
- This compatibility is established by API-surface audit, not by a live run against a bespoke
  `DataStore`. A smoke test against a real custom store is a reasonable future addition; the
  contract above is what such a store must satisfy.
