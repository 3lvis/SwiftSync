# Comment Audit

Audit code comments against one rule: a comment earns its place only when it records something the code,
types, and names cannot express.

## Bar

A comment survives only when it is durable, stated nowhere else, and records one of:

- an external or wire-protocol constraint;
- a non-obvious reason for a design choice;
- a dangerous side effect or framework limitation;
- a concrete TODO whose trigger and required outcome are clear.

Delete narration, restated signatures, tutorial headers, step labels, historical snapshots, and comments
that compensate for weak naming. Keep at most one copy of a fact, at the declaration that owns it.

## Remaining sections

- [ ] **Fake backend implementation** — audit `DemoServerSimulator` and `DemoSeedData`. Preserve durable
      wire-contract facts such as last-writer-wins, idempotency, and `public_id`; remove endpoint narration.
- [ ] **Fake backend tests** — audit `DemoBackendTests` and `UploadEndpointTests`. Remove scenario step
      labels and comments that merely restate assertions.
- [ ] **App sync engine** — audit `DemoSyncEngine`, `DemoAPI`, `ScreenMachines`, and `DemoModels`. Preserve
      offline-drain and failure-policy constraints that the types cannot express.
- [ ] **App sync tests** — audit DemoCore tests. Remove scenario headers and Given/When narration.
- [ ] **Demo UI and UI tests** — preserve real layout/framework gotchas and the required reason for each
      retained UI test; remove interaction narration.
- [ ] **Library tests** — audit SwiftSync tests in smaller coherent slices. Remove tutorial headers,
      filename-restatement headers, Given/When labels, and historical notes.

For each section, format changed Swift files and run the relevant package tests before committing.
