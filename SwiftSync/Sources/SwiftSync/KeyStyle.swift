public enum KeyStyle: Sendable {
    case snakeCase
    case camelCase

    public func transform(_ value: String) -> String {
        switch self {
        case .camelCase:
            return value
        case .snakeCase:
            return toSnakeCase(value)
        }
    }

    private func toSnakeCase(_ value: String) -> String {
        value.syncSnakeCased
    }
}
