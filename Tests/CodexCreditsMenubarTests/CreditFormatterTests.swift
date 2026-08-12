import XCTest
@testable import CodexCreditsMenubar

final class CreditFormatterTests: XCTestCase {
    func testFormatsCreditsAsWholeGroupedOrCompactValues() {
        XCTAssertEqual(CreditFormatter.format(8569.97), "8.6k")
        XCTAssertEqual(CreditFormatter.format(2345), "2.3k")
        XCTAssertEqual(CreditFormatter.format(1000), "1k")
        XCTAssertEqual(CreditFormatter.format(999.7), "1,000")
        XCTAssertEqual(CreditFormatter.format(856.2), "856")
    }
}
