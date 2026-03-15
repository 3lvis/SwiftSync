# Export API Cleanup

## Open items

- [ ] Remove `SyncContainer.export(as:)` from the public API and from README guidance.
- [ ] Remove `SyncContainer.export(as:parent:)` from the public API or replace it with a narrower internal-only path if benchmarks still need it.
- [ ] Audit and update tests, benchmarks, and internal call sites that still depend on bulk export APIs.
- [ ] Rename `exportObject(for:)` to a clearer object-export API, evaluating `draft.export(for:)` against `syncContainer.export(draft)`.
- [ ] Update README and reference docs to present object export as the primary create/update workflow.
