import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum DateType: Sendable {
    case iso8601
    case unixTimestamp
}

enum SyncDateParser {
    private static let unixTimestampSecondsLength = 10

    static func dateFromDateString(_ dateString: String) -> Date? {
        switch dateString.dateType() {
        case .iso8601:
            return dateFromISO8601String(dateString)
        case .unixTimestamp:
            return dateFromUnixTimestampString(dateString)
        }
    }

    static func dateFromUnixTimestampNumber(_ unixTimestamp: NSNumber) -> Date? {
        dateFromUnixTimestampString(unixTimestamp.stringValue)
    }

    static func dateFromUnixTimestampString(_ unixTimestamp: String) -> Date? {
        let trimmed = unixTimestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let bytes = Array(trimmed.utf8)
        var start = 0
        if bytes.first == asciiPlus || bytes.first == asciiMinus {
            start = 1
        }
        guard start < bytes.count else { return nil }
        for idx in start..<bytes.count where !isDigit(bytes[idx]) {
            return nil
        }

        var normalized = trimmed
        if normalized.count > unixTimestampSecondsLength {
            normalized = String(normalized.prefix(unixTimestampSecondsLength))
        }
        guard let seconds = Double(normalized) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func dateFromISO8601String(_ iso8601: String) -> Date? {
        var input = iso8601.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Date-only input is normalized to UTC midnight.
        if isDateOnly(input.utf8) {
            input += "T00:00:00+00:00"
        }
        return parseISODate(input)
    }

    private static func parseISODate(_ input: String) -> Date? {
        let bytes = Array(input.utf8)
        guard bytes.count >= 19 else { return nil }

        guard isDigit(bytes, 0, 4),
              bytes[safe: 4] == asciiMinus,
              isDigit(bytes, 5, 2),
              bytes[safe: 7] == asciiMinus,
              isDigit(bytes, 8, 2),
              (bytes[safe: 10] == asciiT || bytes[safe: 10] == asciiSpace),
              isDigit(bytes, 11, 2),
              bytes[safe: 13] == asciiColon,
              isDigit(bytes, 14, 2),
              bytes[safe: 16] == asciiColon,
              isDigit(bytes, 17, 2) else {
            return nil
        }

        guard let year = int(bytes, 0, 4),
              let month = int(bytes, 5, 2),
              let day = int(bytes, 8, 2),
              let hour = int(bytes, 11, 2),
              let minute = int(bytes, 14, 2),
              let second = int(bytes, 17, 2) else {
            return nil
        }
        guard (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...60).contains(second) else { return nil }

        var index = 19
        var milliseconds = 0

        if bytes[safe: index] == asciiDot {
            index += 1
            var digits = 0
            var msAccumulator = 0

            while let c = bytes[safe: index], isDigit(c) {
                if digits < 3 {
                    msAccumulator = (msAccumulator * 10) + Int(c - asciiZero)
                }
                index += 1
                digits += 1
            }
            guard digits > 0 else { return nil }
            milliseconds = fractionToMilliseconds(prefixValue: msAccumulator, digits: digits)
        }

        var timezoneOffsetSeconds = 0
        if bytes[safe: index] == asciiZ, index + 1 == bytes.count {
            index += 1
        } else if index != bytes.count, let signByte = bytes[safe: index],
                  signByte == asciiPlus || signByte == asciiMinus {
            let sign = signByte == asciiMinus ? -1 : 1
            index += 1

            guard isDigit(bytes, index, 2), let tzHour = int(bytes, index, 2) else { return nil }
            index += 2

            if bytes[safe: index] == asciiColon { index += 1 }
            guard isDigit(bytes, index, 2), let tzMinute = int(bytes, index, 2) else { return nil }
            index += 2
            guard (0...23).contains(tzHour), (0...59).contains(tzMinute) else { return nil }

            timezoneOffsetSeconds = sign * ((tzHour * 3600) + (tzMinute * 60))
        } else if index != bytes.count {
            return nil
        }

        guard index == bytes.count else { return nil }

        var utc = tm()
        utc.tm_year = Int32(year - 1900)
        utc.tm_mon = Int32(month - 1)
        utc.tm_mday = Int32(day)
        utc.tm_hour = Int32(hour)
        utc.tm_min = Int32(minute)
        utc.tm_sec = Int32(second)
        utc.tm_isdst = 0

        let baseEpoch = timegm(&utc)
        guard baseEpoch != -1 else { return nil }

        let epoch = Double(baseEpoch) - Double(timezoneOffsetSeconds)
        return Date(timeIntervalSince1970: epoch + (Double(milliseconds) / 1000.0))
    }

    private static func fractionToMilliseconds(prefixValue: Int, digits: Int) -> Int {
        switch digits {
        case 1:
            return prefixValue * 100
        case 2:
            return prefixValue * 10
        default:
            return prefixValue
        }
    }

    private static func isDateOnly(_ utf8: String.UTF8View) -> Bool {
        let bytes = Array(utf8)
        guard bytes.count == 10 else { return false }
        return isDigit(bytes, 0, 4) &&
            bytes[safe: 4] == asciiMinus &&
            isDigit(bytes, 5, 2) &&
            bytes[safe: 7] == asciiMinus &&
            isDigit(bytes, 8, 2)
    }

    private static func isDigit(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Bool {
        guard start >= 0, length >= 0, start + length <= bytes.count else { return false }
        for idx in start..<(start + length) where !isDigit(bytes[idx]) {
            return false
        }
        return true
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= asciiZero && byte <= asciiNine
    }

    private static func int(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, length > 0, start + length <= bytes.count else { return nil }
        var value = 0
        for idx in start..<(start + length) {
            let byte = bytes[idx]
            guard isDigit(byte) else { return nil }
            value = (value * 10) + Int(byte - asciiZero)
        }
        return value
    }
}

extension String {
    func dateType() -> DateType {
        contains("-") ? .iso8601 : .unixTimestamp
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private let asciiZero: UInt8 = 48
private let asciiNine: UInt8 = 57
private let asciiSpace: UInt8 = 32
private let asciiPlus: UInt8 = 43
private let asciiMinus: UInt8 = 45
private let asciiDot: UInt8 = 46
private let asciiColon: UInt8 = 58
private let asciiT: UInt8 = 84
private let asciiZ: UInt8 = 90
