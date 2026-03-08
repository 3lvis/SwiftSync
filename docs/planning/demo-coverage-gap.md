# Demo Coverage Gap — Public SwiftSync API Not Covered by Demo

**Purpose:** Track only public SwiftSync API surface that is not exercised by Demo runtime code.

**Scope rule:** Coverage here is based on call sites/usages in `Demo/Demo/**` runtime code. `DemoTests` and `SwiftSync` test targets are excluded.

## Open items

### Public protocol-level API not exercised directly by demo runtime call sites

- [ ] Exercise direct `SyncPayload` API usage (`contains`, `value`, `required`) from demo runtime code.
- [ ] Exercise direct `SyncError` handling from demo runtime code.
