import Testing
@testable import SwiftSyncCore
import Foundation

struct SwiftSyncCoreTests {
    @Test("SyncPayload supports id and remoteID conventions")
    func payloadIdentityConventions() throws {
        let payload = SyncPayload(values: ["id": 42])
        let remoteID: Int? = payload.value(for: "remoteID")
        #expect(remoteID == 42)
    }

    @Test("SyncPayload throws for missing required keys")
    func payloadRequiredThrows() {
        let payload = SyncPayload(values: [:])
        #expect(throws: SyncError.self) {
            let _: Int = try payload.required(Int.self, for: "id")
        }
    }

    @Test("Date parser ISO A: timezone-preserving instant")
    func dateParserISOA() {
        assertDate("2015-06-23T14:40:08.123+02:00", equalsUTC: "2015-06-23T12:40:08.123Z")
    }

    @Test("Date parser ISO B: +00:00")
    func dateParserISOB() {
        assertDate("2014-01-01T12:40:08+00:00", equalsUTC: "2014-01-01T12:40:08.000Z")
    }

    @Test("Date parser ISO C: date-only -> UTC midnight")
    func dateParserISOC() {
        assertDate("2014-01-02", equalsUTC: "2014-01-02T00:00:00.000Z")
    }

    @Test("Date parser ISO D: microseconds + timezone")
    func dateParserISOD() {
        assertDate("2014-01-02T12:40:08.123000+00:00", equalsUTC: "2014-01-02T12:40:08.123Z")
    }

    @Test("Date parser ISO E: RFC-822 timezone offset")
    func dateParserISOE() {
        assertDate("2015-09-10T12:40:08.123+0000", equalsUTC: "2015-09-10T12:40:08.123Z")
    }

    @Test("Date parser ISO F: microseconds Z, truncated to milliseconds")
    func dateParserISOF() {
        assertDate("2015-09-10T12:40:08.123456Z", equalsUTC: "2015-09-10T12:40:08.123Z")
    }

    @Test("Date parser ISO G: milliseconds Z")
    func dateParserISOG() {
        assertDate("2015-06-23T19:04:19.911Z", equalsUTC: "2015-06-23T19:04:19.911Z")
    }

    @Test("Date parser ISO H: trailing Z")
    func dateParserISOH() {
        assertDate("2014-03-30T09:13:10Z", equalsUTC: "2014-03-30T09:13:10.000Z")
    }

    @Test("Date parser ISO I: malformed returns nil")
    func dateParserISOI() {
        let parsed = SyncDateParser.dateFromDateString("2014-01-02T00:monsterofthelakeI'mhere00:00.007450+00:00")
        #expect(parsed == nil)
    }

    @Test("Date parser ISO J: centiseconds")
    func dateParserISOJ() {
        assertDate("2016-01-09T12:40:08.12", equalsUTC: "2016-01-09T12:40:08.120Z")
    }

    @Test("Date parser ISO K: no fractional seconds")
    func dateParserISOK() {
        assertDate("2016-01-09T12:40:08", equalsUTC: "2016-01-09T12:40:08.000Z")
    }

    @Test("Date parser ISO L: NSDate-description style")
    func dateParserISOL() {
        assertDate("2009-10-09 12:40:08", equalsUTC: "2009-10-09T12:40:08.000Z")
    }

    @Test("Date parser ISO M: centiseconds with Z")
    func dateParserISOM() {
        assertDate("2017-12-22T18:10:14.07Z", equalsUTC: "2017-12-22T18:10:14.070Z")
    }

    @Test("Date parser ISO N: deciseconds with Z")
    func dateParserISON() {
        assertDate("2017-11-02T17:27:52.2Z", equalsUTC: "2017-11-02T17:27:52.200Z")
    }

    @Test("Date parser ISO O: milliseconds without timezone assume UTC")
    func dateParserISOO() {
        assertDate("2017-12-22T18:10:14.070", equalsUTC: "2017-12-22T18:10:14.070Z")
    }

    @Test("Date parser Unix T1: seconds string")
    func dateParserUnixT1() {
        assertDate("1441888808", equalsUTC: "2015-09-10T12:40:08.000Z")
    }

    @Test("Date parser Unix T2: microseconds string")
    func dateParserUnixT2() {
        assertDate("1441888808000000", equalsUTC: "2015-09-10T12:40:08.000Z")
    }

    @Test("Date parser Unix T3: seconds number")
    func dateParserUnixT3() {
        let parsed = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: 1_441_888_808))
        #expect(parsed == Self.expectedUTC("2015-09-10T12:40:08.000Z"))
    }

    @Test("Date parser Unix T4: microseconds number")
    func dateParserUnixT4() {
        let parsed = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: Int64(1_441_888_808_000_000)))
        #expect(parsed == Self.expectedUTC("2015-09-10T12:40:08.000Z"))
    }

    @Test("Date type classification")
    func dateTypeClassification() {
        #expect("2014-01-02T00:00:00.007450+00:00".dateType() == .iso8601)
        #expect("1441843200000000".dateType() == .unixTimestamp)
    }

    private func assertDate(_ input: String, equalsUTC expected: String) {
        let parsed = SyncDateParser.dateFromDateString(input)
        #expect(parsed == Self.expectedUTC(expected))
    }

    private static func expectedUTC(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
