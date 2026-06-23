/// A measured step of a sync operation. The raw value is the label emitted to `OSSignposter`
/// (visible in Instruments) and the key under which `SyncPerformanceProfiler` accumulates the
/// step's duration — so it is both the signpost name and the profiling-report key.
enum SyncPhase: String {
    case normalizePayload = "normalize-payload"
    case fetchExisting = "fetch-existing"
    case fetchExistingByIdentity = "fetch-existing-by-identity"
    case fetchExistingByParent = "fetch-existing-by-parent"
    case findExisting = "find-existing"
    case filterScope = "filter-scope"
    case fetchParents = "fetch-parents"
    case resolveParent = "resolve-parent"
    case createModel = "create-model"
    case buildIndex = "build-index"
    case applyFields = "apply-fields"
    case applyParent = "apply-parent"
    case applyRelationships = "apply-relationships"
    case deleteDuplicates = "delete-duplicates"
    case deleteMissing = "delete-missing"
    case saveContext = "save-context"
    case relationshipFetch = "relationship-fetch"
    case relationshipFetchByIdentity = "relationship-fetch-by-identity"
    case relationshipIndexByID = "relationship-index-by-id"
    case relationshipApplyToOneForeignKey = "relationship-apply-to-one-foreign-key"
    case relationshipApplyToManyForeignKeys = "relationship-apply-to-many-foreign-keys"
    case relationshipApplyToOneNestedObject = "relationship-apply-to-one-nested-object"
    case relationshipApplyToManyNestedObjects = "relationship-apply-to-many-nested-objects"
}
