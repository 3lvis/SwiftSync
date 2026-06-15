# Custom `DataStore` Compatibility

## Short answer

SwiftSync is **store-agnostic**. It works with any `ModelContainer` — the default SQLite store
or a custom SwiftData `DataStore` — provided the store honours the standard SwiftData semantics
below. SwiftSync only uses public, store-neutral SwiftData APIs; it never configures or reaches
into the store layer (no `DataStoreConfiguration` or store internals).

## The contract a backing store must satisfy

SwiftSync drives sync entirely through standard `ModelContext` operations, so a custom store is
compatible as long as it supports:

1. **Fetching** — `ModelContext.fetch` with a `FetchDescriptor` (`#Predicate` filtering and
   `sortBy`): identity lookups, parent-scope queries, and `@SyncQuery` reads.
2. **Mutation & relationships** — `insert` / `save` / `delete`, plus persistence and faulting of
   to-one and to-many relationships (the upsert and relationship-resolution machinery).
3. **Save notifications** — `ModelContext.didSave` carrying the changed model identifiers.
   **This is the one to watch:** it drives reactive reads. If a store doesn't post `didSave`,
   inbound sync still works, but `@SyncQuery` / `@SyncModel` and the publishers won't auto-refresh
   (you'd refresh manually). See [ios-dirty-tracking-gap.md](ios-dirty-tracking-gap.md) for a
   related `didSave` nuance.
4. **Container initialisation** — `ModelContainer(for:configurations:)`. NSExceptions thrown
   during init are caught by SwiftSync's ObjC bridge on any store.

To confirm compatibility for a specific store, exercise those four behaviours end-to-end. This
list is the durable contract — SwiftSync's internal call sites will change across refactors, but
what it *requires of a store* is the above.

## Caveats

- Unique-constraint **upsert** behaviour belongs to the store, not SwiftSync. The rule in
  [property-mapping-contract.md](property-mapping-contract.md) (uniqueness only on the sync
  identity) applies on any store.
- This contract is derived from the behaviours SwiftSync uses, not from a live run against a
  bespoke `DataStore`. A smoke test against a real custom store is a reasonable future addition.
