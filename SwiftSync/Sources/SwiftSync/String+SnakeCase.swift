import Foundation

extension String {
    var syncSnakeCased: String {
        guard !isEmpty else { return self }
        var output = ""
        let scalars = Array(unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let current = scalar.syncScalarClass
            if index > 0, current == .upper {
                let previous = scalars[index - 1].syncScalarClass
                let next = index + 1 < scalars.count ? scalars[index + 1].syncScalarClass : nil
                let startsNewWord = previous == .lower || previous == .digit
                let endsAcronym = previous == .upper && next == .lower
                if startsNewWord || endsAcronym, output.last != "_" {
                    output.append("_")
                }
            }
            output.append(String(scalar).lowercased())
        }
        return output
    }
}

private enum SyncScalarClass {
    case upper
    case lower
    case digit
    case other
}

extension UnicodeScalar {
    fileprivate var syncScalarClass: SyncScalarClass {
        if CharacterSet.uppercaseLetters.contains(self) { return .upper }
        if CharacterSet.lowercaseLetters.contains(self) { return .lower }
        if CharacterSet.decimalDigits.contains(self) { return .digit }
        return .other
    }
}
