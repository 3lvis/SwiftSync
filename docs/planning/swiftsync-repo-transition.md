# SwiftSync Repo Transition

## Open items

- [ ] Freeze the old `Sync` Core Data codebase on a legacy branch and tag the final legacy release.
- [ ] Rename the GitHub repository from `3lvis/Sync` to `3lvis/SwiftSync`.
- [ ] Replace the default branch contents with the current SwiftSync codebase.
- [ ] Set the package identity, library product, and import path to `SwiftSync` everywhere.
- [ ] Rewrite the top of the new root `README` to state that this is the SwiftData-era successor to the old Core Data `Sync`.
- [ ] Add a migration guide that explains this is not a drop-in upgrade from legacy `Sync`.
- [ ] Add a legacy notice to the preserved Core Data branch README pointing new SwiftData users to `SwiftSync`.
- [ ] Verify GitHub repo redirects, package URL resolution, and Swift Package Manager dependency resolution after the rename.
- [ ] Publish the new major version from the renamed repository.
