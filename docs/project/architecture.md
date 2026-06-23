# Architecture: layering an app on SwiftSync

How an app is built on top of SwiftSync, using the demo (`Demo` + `DemoCore`) as the reference
implementation. The guiding rule is **strict, one-directional layering**: each layer knows only the layer
directly beneath it, and nothing about the ones further down. Get the separation right and the rest —
generics, offline, reconnect, the failures inbox — falls out cleanly.

## The four layers

```
 ┌─ Views (SwiftUI *or* UIKit) ──────────────────────────────────┐
 │  Pure rendering. Bind to ONE per-screen machine, which gives    │
 │  them both reactive DATA and STATUS. Know nothing of networking │
 │  or storage internals. The framework is interchangeable — only  │
 │  the last-mile binding differs (see "Framework-agnostic").      │
 └───────────────────────────▲────────────────────────────────────┘
                              │ render(state) / send(event)
 ┌─ Screen state machines (per screen) ──────────────────────────┐
 │  One per screen. Host the reactive store query (a               │
 │  SyncQueryPublisher / SyncModelPublisher) that exposes DATA, and │
 │  own the screen's STATUS lifecycle (loading/loaded/empty/error).│
 │  Ask the engine for data; know the engine, NOT networking/store.│
 └───────────────────────────▲────────────────────────────────────┘
                              │ "load project X's tasks" / "push"
 ┌─ DemoSyncEngine  (NETWORKING + ORCHESTRATION) ────────────────┐
 │  The ONLY layer that talks to the backend. Decides ordering    │
 │  (push-before-pull, drain-on-reconnect), which endpoint, when.  │
 │  Holds cross-cutting sync STATUS (isOffline, isSyncing,         │
 │  pending/failed counts, the failures inbox). Uses SwiftData     │
 │  directly for plain local reads/writes, and SwiftSync for the   │
 │  SYNC magic — it never reimplements SwiftSync's sync internals. │
 └───────────────────────────▲────────────────────────────────────┘
                              │ "store these" / "what changed locally?"
 ┌─ SwiftSync  (STORAGE) ────────────────────────────────────────┐
 │  The magic. Stores server data into SwiftData; detects local   │
 │  edits; brackets the push token. Knows NOTHING about networking │
 │  or screens.                                                    │
 └─────────────────────────────────────────────────────────────────┘
```

**Dependency direction is downward only.** A view never imports a networking type; SwiftSync never knows
an HTTP request exists. The one deliberate exception is the engine: it depends on *both* layers below it —
SwiftData directly for plain local reads/writes, and SwiftSync for the sync magic (see the engine box
above). Otherwise each arrow above is the *only* thing a layer knows about the one below it.

## What each layer owns — and must not know

| Layer | Owns | Must NOT know |
|---|---|---|
| **Views** | rendering; reactive reads of the store; binding a screen's status | networking; storage internals; ordering |
| **Screen state machines** | one screen's `loading/loaded/empty/failed` + transitions | *how* data is fetched or stored |
| **DemoSyncEngine** | the backend API; ordering/when; cross-cutting status + the inbox | *how* SwiftSync persists or diffs |
| **SwiftSync** | persisting, inbound apply, local-change detection, the push token | that a network, or a screen, exists |

## SwiftSync's role: the storage floor

SwiftSync is **storage, and only storage**. Its public surface is small and networking-free:

- **`@Syncable @Model`** — the consumer annotates a SwiftData model once; the macro generates all the
  sync plumbing (`make` / `apply` / `applyRelationships` / `export` / identity). Zero hand-written sync
  code per model.
- **Inbound apply** — `SyncContainer.sync(payload:as:)` (a *group* / collection) and
  `SyncContainer.sync(item:as:)` (a single *item*), with `parent:` + `relationship:` variants to scope a
  child collection under its parent. This is the "JSON in → rows in the store" magic.
- **Local-change detection** — `SwiftSync.pendingChanges(for:in:)` reads the store's own SwiftData history
  (since a per-type token) and reports the un-pushed local inserts/updates/deletes. No side table, no
  flags on the model.
- **The push bracket** — `SwiftSync.withPendingChanges(for:in:) { pending in … }` reads pending, hands it
  to a closure (the caller does the network), and — only on a clean return — advances the token.
  Inbound sync separately removes its own author-tagged history; app-authored history remains available
  to other consumers. The bracket is the *storage* half of a push; the closure is the *networking* half
  (supplied from the layer above).
- **`SyncContainer`** is the store handle: `@unchecked Sendable` (its bulk `sync(payload:)` runs off the
  main actor by design), no UI state, no orchestration.

Everything else — *when* to push, *which* endpoint, reachability, the failures inbox, loading status — is
**not** SwiftSync's concern. (See "Hard-won lessons" for why we enforce this.)

## Generics & the group/item split

The same two ideas repeat in two layers, both generic over the model type `T`:

- **Networking layer (the engine):** fetch a **group** (`[T]`) vs an **item** (`T`) from the backend — the
  shape `Backend.fetchItems<T>()` / `fetchItem<T>()` (cf. flytt-ios). The endpoints differ; the *plumbing*
  is one generic shape.
- **Storage layer (SwiftSync):** store a **group** (`sync(payload: [T])`) vs an **item**
  (`sync(item: T)`), with `parent:` + `relationship:` for scoping a child group under its parent.

Models opt in by being `@Syncable` (and, for offline, marking the identity
`@Attribute(.unique, .preserveValueOnDeletion)`). That single attribute is the entire offline opt-in — it
keeps a deleted row's id alive in history so deletions can be detected and pushed.

## Data flow: data from the store, status from the machine

This is where a stored app differs from a stateless one (flytt-ios carries data inside its `ViewState`
because it has no store). Here the two streams are split, and **the per-screen machine hosts both**:

- **Data** is a reactive store query — a `SyncQueryPublisher` / `SyncModelPublisher` the machine holds
  (scoped by relationship, e.g. `\Task.project` + `projectID`). It observes
  `SyncContainer.didSaveChangesNotification` and reloads on any store change, so it never rides through a
  network payload or a `.loaded([…])` enum case. The machine re-exposes it as `rows` / `tasks` / `task`.
- **Status** (`loading / empty / error`) is the machine's `ScreenLoadState`, derived from the load
  lifecycle (and the data count, for the empty-vs-content distinction).

So a typical screen — the view binds to **one** observable (the machine), which gives it both:

```
view:    binds machine.tasks (reactive DATA)  +  machine.contentState (STATUS)
machine: hosts SyncQueryPublisher<Task>(relationship: \.project, relationshipID:)  ← reactive data
         + ScreenLoadMachine ("engine, load project X")                            ← status
engine:  fetch (networking) → SwiftSync.sync(...) (storage) → store saves
SwiftSync: persists → didSaveChangesNotification → the machine's publisher reloads → view re-renders
```

The engine fills the store; the machine's publisher observes the store; the view binds the machine. The
view never holds a query or a payload — it's pure presentation over one observable. (The failures inbox
follows the same pattern: a `SyncQueryPublisher<Task>` predicated on `syncFailureReason != nil`.)

## The offline / push story

Writes have two honest modes — and we keep both:

- **Online write = network-first.** Call the server, let it confirm, *then* sync the confirmed result into
  the store. Errors are synchronous and inline. (Server-authoritative; the proper UX.)
- **Offline write = optimistic + queued.** Apply locally (a normal SwiftData write), and the engine drains
  the queue on reconnect.

The **push/drain orchestration lives in the engine** (it's *when/ordering*, i.e. networking-layer policy):

- The engine calls `SwiftSync.withPendingChanges(for:in:) { pending in <its upload> }`. SwiftSync brackets
  the storage token; the engine's closure does the transport (`/sync/upload`).
- The client id **is** the row's identity the server adopts as its `public_id` — an idempotent upsert, so
  the closure returns only the **rejected** rows (`[SyncPendingChangesFailure]`); everything else is confirmed by
  complement. A `stale` result means the server won last-writer-wins: adopt its state, not a failure.
- **Reconnect** re-drains (the engine triggers it when `isOffline` flips back). **Concurrent drains
  coalesce** — a push-before-pull awaits the in-flight drain instead of racing the upload.
- **Inbox safety:** a drain that *throws* (transport/server error) is not a clean drain — the engine does
  not touch the inbox on a throw, so a transient failure can't wipe `syncFailureReason`. Only a completed
  drain re-stamps it.
- SwiftSync persists **no** per-row failure state; the failures inbox (`syncFailureReason`, discard) is the
  app's concern, in the engine.

## State machines (per screen)

A screen with a **load lifecycle** gets a state machine (`ScreenMachines`): the presentation layer between
a view and the engine, hosting the screen's reactive store query (data), modelling the
`loading/loaded/empty/error` lifecycle (status), and asking the engine to load. It is *not* redundant with
the engine — the engine owns **cross-cutting, app-wide** sync status (the offline toggle, badge counts,
the inbox); each machine owns **one screen's** data+status. The data is a live store query (it reloads on
any store change), not a snapshot the machine fetches once.

A screen with **no load lifecycle** doesn't need a machine. The failures inbox (`FailuresSheet`) is the
example: it has no loading/empty/error states to model, so it holds its `SyncQueryPublisher` directly in
the view (and the `DemoSyncEngine` for the discard action). The rule isn't "every screen has a machine" —
it's "data is a reactive store query, status is modelled where a lifecycle exists." A machine is just the
home for that pairing when a lifecycle warrants it.

## Framework-agnostic: SwiftUI *and* UIKit

The layering is deliberately **UI-framework-agnostic** — and the demo proves it. Every screen except one
is SwiftUI; the **Projects list is UIKit** (`ProjectsViewController: UITableViewController`) precisely to
show SwiftSync works the same either way. Crucially, nothing below the view changes: the UIKit controller
uses the **same `ProjectsViewMachine`** (same hosted `SyncQueryPublisher`, same `ScreenLoadMachine`, same
engine, same SwiftSync) as a SwiftUI screen would. Only the **last-mile binding** differs:

| | how the view observes the machine | how it renders the list |
|---|---|---|
| **SwiftUI** | `@Observable` binding — re-renders on change automatically | a `List`/`ForEach` over `machine.rows` |
| **UIKit** | `observeContinuously { … }` (a `withObservationTracking` loop over the same `@Observable` machine) | re-applies an `NSDiffableDataSourceSnapshot` of `machine.rows.map(\.id)` |

So the reactive store query (`SyncQueryPublisher`, observing `didSaveChangesNotification`) drives a
`UITableViewDiffableDataSource` exactly as it drives a SwiftUI `List` — same data, same status enum
(`ProjectsListStatusState`), same machine. SwiftSync's reactivity is an `@Observable` contract, not a
SwiftUI feature, so any UIKit view can consume it through `withObservationTracking`. The framework is a
view-layer detail; the architecture (machine → engine → SwiftSync) is identical underneath.

## Hard-won lessons (why the separation is enforced, not incidental)

- **Don't fold orchestration into storage.** We tried putting the drain/reconnect/status driver onto
  `SyncContainer`. It forced `@MainActor` members onto an otherwise-`Sendable`, off-main type — a real
  mixed-isolation smell. That smell *was* the layer boundary talking: orchestration is networking-layer
  policy, so it belongs in the engine, not the store. `SyncContainer` stays a pure `Sendable` storage
  primitive.
- **No UI state in the library.** `pendingCount` / `failedCount` are derivable (from `pendingChanges` +
  the drain's failures) and are a UI concern — they live in the engine's `@Observable` state, not the
  library.
- **No speculative library "sync session."** A generic library coordinator had exactly one consumer (the
  demo) and its parts (endpoints, the offline-error type, the inbox) are app-specific. Per "no abstraction
  without a consumer," the consolidation that pays off is *app-side* — one coherent engine — not a bigger
  library. Extract the generic core only when a second real consumer appears to shape it.
- **The library stays the magic, nothing more.** Its value is that the app above it never thinks about
  storage; that only holds if storage never leaks upward (networking) or downward-of-its-concern (UI).

## Reference: flytt-ios parallels

`code/flytto/flytt-ios` (UIKit) is the same shape minus the storage floor: `Backend` is the networking
facade (generic `fetchItems<T>` / `fetchItem<T>` over `Formable`/`Listable`/`Detailable`), and per-screen
`Controller`s hold `ViewState` enums (`loading/loaded/empty/failed`). Map: `Backend` ≈ DemoSyncEngine's
networking, `Controller` ≈ a screen state machine, `ViewState` ≈ the machine's state. flytt is stateless
(server is truth), so its `ViewState` *carries* the data; SwiftSync adds the store, so here data comes
from the store reactively and the machine's state carries only status. The generics, the layering, and the
four-case state shape transfer directly; the framework (UIKit vs SwiftUI) does not matter.
