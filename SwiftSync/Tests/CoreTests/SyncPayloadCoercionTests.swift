import Foundation
import Testing
@testable import Core

struct SyncPayloadCoercionTests {
    @Test("SyncPayload coerces string and integer into Double")
    func coercesDouble() {
        let stringPayload = SyncPayload(values: ["value": "3.14"])
        let intPayload = SyncPayload(values: ["value": 7])

        let fromString: Double? = stringPayload.value(for: "value")
        let fromInt: Double? = intPayload.value(for: "value")

        #expect(fromString == 3.14)
        #expect(fromInt == 7.0)
    }

    @Test("SyncPayload coerces number-like inputs into Decimal")
    func coercesDecimal() {
        let stringPayload = SyncPayload(values: ["value": "12.50"])
        let intPayload = SyncPayload(values: ["value": 9])
        let doublePayload = SyncPayload(values: ["value": 4.25])

        let fromString: Decimal? = stringPayload.value(for: "value")
        let fromInt: Decimal? = intPayload.value(for: "value")
        let fromDouble: Decimal? = doublePayload.value(for: "value")

        #expect(fromString == Decimal(string: "12.50"))
        #expect(fromInt == Decimal(9))
        #expect(fromDouble == Decimal(string: "4.25"))
    }

    @Test("SyncPayload coerces URL from string")
    func coercesURL() {
        let payload = SyncPayload(values: ["url": "https://example.com/path"])
        let value: URL? = payload.value(for: "url")
        #expect(value?.absoluteString == "https://example.com/path")
    }

    @Test("SyncPayload coerces Bool from common scalar forms")
    func coercesBool() {
        let trueStringPayload = SyncPayload(values: ["value": "true"])
        let falseStringPayload = SyncPayload(values: ["value": "false"])
        let trueNumberPayload = SyncPayload(values: ["value": 1])
        let falseNumberPayload = SyncPayload(values: ["value": 0])

        let trueFromString: Bool? = trueStringPayload.value(for: "value")
        let falseFromString: Bool? = falseStringPayload.value(for: "value")
        let trueFromNumber: Bool? = trueNumberPayload.value(for: "value")
        let falseFromNumber: Bool? = falseNumberPayload.value(for: "value")

        #expect(trueFromString == true)
        #expect(falseFromString == false)
        #expect(trueFromNumber == true)
        #expect(falseFromNumber == false)
    }

    @Test("SyncPayload strictValue remains non-coercive for numeric string")
    func strictValueRemainsStrict() {
        let payload = SyncPayload(values: ["id": "42"])
        let strictInt: Int? = payload.strictValue(for: "id")
        #expect(strictInt == nil)
    }
}
