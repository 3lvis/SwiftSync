import Foundation

public enum DateType: Sendable {
    case iso8601
    case unixTimestamp
}

public enum SyncDateParser {
    private static let unixTimestampSecondsLength = 10

    public static func dateFromDateString(_ dateString: String) -> Date? {
        switch dateString.dateType() {
        case .iso8601:
            return dateFromISO8601String(dateString)
        case .unixTimestamp:
            return dateFromUnixTimestampString(dateString)
        }
    }

    public static func dateFromUnixTimestampNumber(_ unixTimestamp: NSNumber) -> Date? {
        dateFromUnixTimestampString(unixTimestamp.stringValue)
    }

    public static func dateFromUnixTimestampString(_ unixTimestamp: String) -> Date? {
        let trimmed = unixTimestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var chars = Array(trimmed)
        if chars.first == "+" || chars.first == "-" {
            chars.removeFirst()
        }
        guard !chars.isEmpty, chars.allSatisfy(\.isNumber) else { return nil }

        var normalized = trimmed
        if normalized.count > unixTimestampSecondsLength {
            normalized = String(normalized.prefix(unixTimestampSecondsLength))
        }
        guard let seconds = Double(normalized) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func dateFromISO8601String(_ iso8601: String) -> Date? {
        var input = iso8601.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Date-only input is normalized to UTC midnight.
        if isDateOnly(input) {
            input += "T00:00:00+00:00"
        }

        // NSDate-description style.
        if input.count == 19 {
            var chars = Array(input)
            if chars.indices.contains(10), chars[10] == " " {
                chars[10] = "T"
                input = String(chars)
            }
        }

        return parseISODate(input)
    }

    private static func parseISODate(_ input: String) -> Date? {
        let chars = Array(input)
        guard chars.count >= 19 else { return nil }

        guard isDigit(chars, 0, 4),
              chars[safe: 4] == "-",
              isDigit(chars, 5, 2),
              chars[safe: 7] == "-",
              isDigit(chars, 8, 2),
              chars[safe: 10] == "T",
              isDigit(chars, 11, 2),
              chars[safe: 13] == ":",
              isDigit(chars, 14, 2),
              chars[safe: 16] == ":",
              isDigit(chars, 17, 2) else {
            return nil
        }

        guard let year = int(chars, 0, 4),
              let month = int(chars, 5, 2),
              let day = int(chars, 8, 2),
              let hour = int(chars, 11, 2),
              let minute = int(chars, 14, 2),
              let second = int(chars, 17, 2) else {
            return nil
        }

        var index = 19
        var milliseconds = 0

        if chars[safe: index] == "." {
            index += 1
            let fractionStart = index
            while let c = chars[safe: index], c.isNumber {
                index += 1
            }
            let digits = index - fractionStart
            guard digits > 0 else { return nil }
            guard let fractionValue = int(chars, fractionStart, digits) else { return nil }
            milliseconds = fractionToMilliseconds(value: fractionValue, digits: digits)
        }

        var timezoneOffsetSeconds = 0
        if index == chars.count {
            timezoneOffsetSeconds = 0
        } else if chars[safe: index] == "Z", index + 1 == chars.count {
            timezoneOffsetSeconds = 0
            index += 1
        } else if chars[safe: index] == "+" || chars[safe: index] == "-" {
            guard let signChar = chars[safe: index] else { return nil }
            let sign = signChar == "-" ? -1 : 1
            index += 1

            guard isDigit(chars, index, 2) else { return nil }
            guard let tzHour = int(chars, index, 2) else { return nil }
            index += 2

            let tzMinute: Int
            if chars[safe: index] == ":" {
                index += 1
                guard isDigit(chars, index, 2) else { return nil }
                guard let value = int(chars, index, 2) else { return nil }
                tzMinute = value
                index += 2
            } else {
                guard isDigit(chars, index, 2) else { return nil }
                guard let value = int(chars, index, 2) else { return nil }
                tzMinute = value
                index += 2
            }

            timezoneOffsetSeconds = sign * ((tzHour * 3600) + (tzMinute * 60))
        } else {
            return nil
        }

        guard index == chars.count else { return nil }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let baseUTC = components.date else { return nil }

        let epoch = baseUTC.timeIntervalSince1970 - Double(timezoneOffsetSeconds)
        return Date(timeIntervalSince1970: epoch + (Double(milliseconds) / 1000.0))
    }

    private static func fractionToMilliseconds(value: Int, digits: Int) -> Int {
        switch digits {
        case 1:
            return value * 100
        case 2:
            return value * 10
        default:
            let scale = pow10(digits - 3)
            return value / scale
        }
    }

    private static func pow10(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var result = 1
        for _ in 0..<n {
            result *= 10
        }
        return result
    }

    private static func isDateOnly(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 10 else { return false }
        return isDigit(chars, 0, 4) &&
            chars[safe: 4] == "-" &&
            isDigit(chars, 5, 2) &&
            chars[safe: 7] == "-" &&
            isDigit(chars, 8, 2)
    }

    private static func isDigit(_ chars: [Character], _ start: Int, _ length: Int) -> Bool {
        guard start >= 0, length >= 0, start + length <= chars.count else { return false }
        for i in start..<(start + length) where !chars[i].isNumber {
            return false
        }
        return true
    }

    private static func int(_ chars: [Character], _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, length > 0, start + length <= chars.count else { return nil }
        return Int(String(chars[start..<(start + length)]))
    }
}

public extension String {
    func dateType() -> DateType {
        contains("-") ? .iso8601 : .unixTimestamp
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
