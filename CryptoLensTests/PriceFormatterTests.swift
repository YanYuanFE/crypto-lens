import XCTest
@testable import CryptoLens

final class PriceFormatterTests: XCTestCase {
    func testUSDPriceThresholdsAndTrailingZeros() {
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "1234.5")!), "$1,234.50")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "1")!), "$1.00")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.01")!), "$0.01")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.1200")!), "$0.12")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.009999")!), "$0.009999")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.000001")!), "$0.000001")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.00123456")!), "$0.001235")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "0.000000123")!), "$1.23e−07")
        XCTAssertEqual(PriceFormatter.price(Decimal(string: "-0.000000123")!), "$-1.23e−07")
    }

    func testChangeAlwaysShowsDirectionAndNilStaysEmpty() {
        XCTAssertEqual(PriceFormatter.change(Decimal(string: "2.14")), "+2.14%")
        XCTAssertEqual(PriceFormatter.change(Decimal(string: "-0.32")), "−0.32%")
        XCTAssertEqual(PriceFormatter.change(0), "+0.00%")
        XCTAssertEqual(PriceFormatter.change(nil), "")
    }

    func testAccessibilityFormattingDoesNotReadScientificNotation() {
        XCTAssertEqual(PriceFormatter.accessibilityPrice(Decimal(string: "0.000000123")!), "0.000000123 美元")
        XCTAssertEqual(PriceFormatter.accessibilityChange(Decimal(string: "-0.32")), "24 小时下跌 0.32 百分比")
    }
}
