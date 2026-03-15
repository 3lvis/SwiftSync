# Documentation

Start here if you are evaluating SwiftSync for a real app.

SwiftSync is for iOS teams that want SwiftData to stay the local source of truth while syncing conventional JSON APIs in and out with explicit semantics.

If you want the shortest description of the project:
- define your models once
- sync payloads into SwiftData
- export local models back to JSON
- let SwiftUI/UIKit read the local store reactively

## Best Starting Points

- New to the project: read [README.md](../README.md)
- Need the backend contract first: [backend-contract.md](project/backend-contract.md)
- Need reactive UI reads: [reactive-reads.md](project/reactive-reads.md)
- Need parent-scoped sync/query rules: [parent-scope.md](project/parent-scope.md)
- Need mapping/import/export rules: [property-mapping-contract.md](project/property-mapping-contract.md)
- Need relationship edge-case guidance: [relationship-integrity.md](project/relationship-integrity.md)
- Migrating from legacy `Sync`: [migrating-from-sync.md](project/migrating-from-sync.md)
- Need short answers first: [faq.md](project/faq.md)

## Recommended Reading Order

1. [README.md](../README.md)
2. [backend-contract.md](project/backend-contract.md)
3. [reactive-reads.md](project/reactive-reads.md)
4. [property-mapping-contract.md](project/property-mapping-contract.md)

## Project Docs

- [backend-contract.md](project/backend-contract.md): recommended API shape for low-boilerplate sync
- [faq.md](project/faq.md): short answers and cross-links
- [manual-syncupdatablemodel.md](project/manual-syncupdatablemodel.md): manual conformance path
- [migrating-from-sync.md](project/migrating-from-sync.md): how to approach the old Core Data `Sync` -> SwiftSync transition
- [parent-scope.md](project/parent-scope.md): parent-scoped identity and query rules
- [property-mapping-contract.md](project/property-mapping-contract.md): key mapping, `null`, export, and coercion rules
- [reactive-reads.md](project/reactive-reads.md): `@SyncQuery`, `@SyncModel`, publishers, and app architecture guidance
- [relationship-integrity.md](project/relationship-integrity.md): many-to-many inverse anchor guidance
- [fetch-strategy-under-load.md](project/fetch-strategy-under-load.md): performance framing for query strategy
- [ios-dirty-tracking-gap.md](project/ios-dirty-tracking-gap.md): known SwiftData observation caveat

## Internal Project Workflow Docs

- [bug-solving-playbook.md](project/bug-solving-playbook.md)
- [test-running-playbook.md](project/test-running-playbook.md)
