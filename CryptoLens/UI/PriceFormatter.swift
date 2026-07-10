import Foundation

enum PriceFormatter {
    static func price(_ value: Decimal) -> String {
        let absolute = NSDecimalNumber(decimal: value).doubleValue.magnitude
        if absolute < 0.000001, absolute > 0 {
            return "$" + String(format: "%.2e", NSDecimalNumber(decimal: value).doubleValue)
                .replacingOccurrences(of: "e-", with: "e−")
                .replacingOccurrences(of: "e+", with: "e+")
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = absolute >= 1 ? 2 : 0
        formatter.maximumFractionDigits = absolute >= 1 ? 2 : (absolute >= 0.01 ? 4 : 6)
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$—"
    }

    static func change(_ value: Decimal?) -> String {
        guard let value else { return "" }
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number < 0 ? "−" : "+"
        return sign + String(format: "%.2f%%", abs(number))
    }

    static func accessibilityPrice(_ value: Decimal) -> String {
        var value = value
        return String(localized: "\(NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))) 美元")
    }

    static func accessibilityChange(_ value: Decimal?) -> String {
        guard let value else { return "" }
        var magnitude = value < 0 ? -value : value
        let magnitudeText = NSDecimalString(&magnitude, Locale(identifier: "en_US_POSIX"))
        return value < 0
            ? String(localized: "24 小时下跌 \(magnitudeText) 百分比")
            : String(localized: "24 小时上涨 \(magnitudeText) 百分比")
    }
}
