# SwiftSync Demo Field Reduction Plan (App + Fake Backend)

## Goal

Reduce demo model/backend fields to the minimum set that still proves SwiftSync's core value:

- staged sync reads
- parent/to-many reactive queries
- property mapping (including reserved key example: `description`)
- realistic create/update/delete flows

## Current Status (2026-02-22)

### Decisions / Implementation Status

- [X] Remove `User.avatarSeed`
- [X] Remove `Tag.colorHex`
- [X] Remove `Task.dueDate`
- [X] Remove `Comment.updatedAt` (comments remain create/read-focused for now)
- [ ] Re-decide `Task.priority` after CRUD UI scope is finalized

This plan covers both:

- Demo app SwiftData models (`Demo/Demo/Models/DemoModels.swift`)
- fake backend schema/payloads (`DemoBackend`)

## Scope Rules

- Keep fields only if they are required for:
  - a user-visible UI interaction
  - a relationship demonstration
  - a sync behavior demonstration
  - a write-flow contract we plan to ship in the demo
- Remove fields that are only visual filler or duplicate another field's purpose.
- Defer any field reduction that would block current read-path stability until write flows are in place.

## Current Field Inventory (Baseline)

### Project

- `id`
- `name`
- `status`
- `updatedAt`

### User

- `id`
- `displayName`
- `avatarSeed`
- `role`
- `updatedAt`

### Tag

- `id`
- `name`
- `colorHex`
- `updatedAt`

### Task

- `id`
- `projectID`
- `assigneeID`
- `title`
- `descriptionText` (`@RemoteKey("description")`)
- `state`
- `priority`
- `dueDate`
- `updatedAt`

### Comment

- `id`
- `taskID`
- `authorUserID`
- `body`
- `createdAt`
- `updatedAt`

## Proposed Target Field Set (Recommended)

This target keeps the demo strong while reducing maintenance and write-surface complexity.

### Keep (High Value)

#### Project

- `id` (identity)
- `name` (UI + create/update flow)
- `status` (simple update field, list UI variance)
- `updatedAt` (server-owned mutation proof)

#### User

- `id` (identity)
- `displayName` (UI + create/update flow)
- `role` (simple update/select field)
- `updatedAt` (server-owned mutation proof)

#### Tag

- `id` (identity)
- `name` (UI + many-to-many labeling)
- `updatedAt` (server-owned mutation proof)

#### Task

- `id` (identity)
- `projectID` (relationship FK)
- `assigneeID` (optional FK, to-one demo)
- `title` (core UI + create/update)
- `descriptionText` / remote `"description"` (reserved-name/property-mapping demo)
- `state` (simple update/select field)
- `updatedAt` (server-owned mutation proof)

#### Comment

- `id` (identity)
- `taskID` (relationship FK)
- `authorUserID` (relationship FK)
- `body` (core UI + create/update or create-only)
- `createdAt` (display ordering)

### Remove First (Low Value / High Maintenance)

- [X] `User.avatarSeed`
  - mostly visual filler
  - adds payload/schema/seed complexity
- [X] `Tag.colorHex`
  - visual polish only; not needed to prove many-to-many sync
- [ ] `Task.priority`
  - useful, but duplicates the role of `state` for "task metadata updates"
  - also used for sorting today, so requires query/UI updates
- [X] `Task.dueDate`
  - not used in core demo interactions
- [X] `Comment.updatedAt`
  - only needed if comment editing is in scope; if comments stay create-only + delete, `createdAt` is enough

### Keep for Now, Re-evaluate After CRUD

- `Task.priority`
  - if we decide to keep "quick edit metadata" richer than just `state`, retain it
- `Project.status`
  - if project updates are dropped from Phase 2, this becomes a removal candidate

## Reduction Strategy (Order Matters)

### Phase A: Decide Target Contract (No Code Changes Yet)

1. Confirm which write interactions the demo will actually ship (especially user/project updates vs create-only).
2. Freeze the target field set before changing seed data or backend schema.
3. Update planning docs so CRUD plan and field plan agree.

### Phase B: Remove UI-Only Filler Fields First (Safe)

1. [X] Remove `User.avatarSeed` and `Tag.colorHex` from:
   - SwiftData demo models
   - fake backend SQLite schema
   - seed data generator
   - backend payloads
   - UI rendering
2. [X] Rebuild demo and run backend tests.

Why first:
- lowest sync risk
- no relationship semantics affected

### Phase C: Remove Low-Value Task/Comment Fields

1. [X] Remove `Task.dueDate` (if no imminent UI use).
2. [ ] Decide `Task.priority` keep/remove based on CRUD UI scope.
3. [X] Remove `Comment.updatedAt` if comments remain create/delete only.

Why separate from Phase B:
- `Task` is the most-connected model and easiest place to create regressions.

### Phase D: Align Sorting/Queries with Reduced Fields

If `Task.priority` is removed:

1. Replace task sorting with stable alternatives (e.g. `state`, `title`, `id`, or `updatedAt` + `id`).
2. Update all `@SyncQuery(Task.self, ...)` call sites consistently.

### Phase E: Lock Contract and Document It

1. Update demo planning docs and any demo-specific docs/examples.
2. Keep one source of truth for the demo payload contract (backend plan + code).

## TDD / Test Plan (Required)

### DemoBackend Package Tests

- Add/adjust tests before schema changes:
  - read payload keys for affected endpoints
  - seed bootstrap still succeeds after column removal
  - write mutations still return expected keys

### Demo App Build Safety

- Build the Demo app after each field-removal phase.
- Verify affected screens still render:
  - Projects list/detail
  - Users list/detail
  - Task detail
  - Tag drill-in

## Acceptance Criteria

1. Demo models and backend schema use the agreed reduced field set.
2. No demo UI references removed fields.
3. `DemoBackend` tests pass after field removals.
4. Demo app builds and read flows still work.
5. CRUD plan remains aligned with the fields that still exist.

## Risks to Avoid

- Removing fields before deciding CRUD scope (causes re-add churn)
- Changing backend payload keys without updating demo sync expectations
- Removing `updatedAt` too aggressively and losing "server-owned mutation" proof in the demo
- Removing the reserved-key mapping example (`description`) and losing a valuable property-mapping demo
