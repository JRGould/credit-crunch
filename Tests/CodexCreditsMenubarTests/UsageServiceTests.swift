import Foundation
import XCTest
@testable import CodexCreditsMenubar

final class UsageServiceTests: XCTestCase {
    func testParserAcceptsNestedIndividualLimitWithNumericStringsAndNumbers() throws {
        let data = """
        {"spend_control":{"individual_limit":{"limit":"100","used":25,"remaining_percent":"75","reset_at":"reset"}}}
        """.data(using: .utf8)!
        let value = try UsageService.parseSpendControl(data)

        XCTAssertEqual(value.limit, 100)
        XCTAssertEqual(value.used, 25)
        XCTAssertEqual(value.remaining, 75)
        XCTAssertEqual(value.remainingPercent, 75)
    }

    func testParserUsesGenericErrorForMissingNullAndMalformedContracts() {
        for fixture in ["{}", "{\"spend_control\":null}", "not-json"] {
            XCTAssertThrowsError(try UsageService.parseSpendControl(Data(fixture.utf8))) { error in
                guard case UsageServiceError.malformedResponse = error else {
                    return XCTFail("Expected generic malformed response error, got \(error)")
                }
            }
        }
    }
}
