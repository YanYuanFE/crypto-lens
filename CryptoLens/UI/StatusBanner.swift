import Foundation

enum StatusCondition: Hashable, Sendable {
    case persistenceFailure
    case corruptedStore
    case classificationUnavailable
    case configuredKeyInvalid
    case missingKey
    case rateLimited
    case offline
    case timeout
    case serverError
    case refreshFailed

    fileprivate var priority: Int {
        switch self {
        case .persistenceFailure: 100
        case .corruptedStore: 99
        case .classificationUnavailable: 98
        case .configuredKeyInvalid: 80
        case .missingKey: 79
        case .rateLimited: 60
        case .offline: 40
        case .timeout: 39
        case .serverError: 38
        case .refreshFailed: 20
        }
    }

    var message: String {
        switch self {
        case .persistenceFailure: "更改未保存"
        case .corruptedStore: "本地数据已重置"
        case .classificationUnavailable: "股票代币分类暂不可用"
        case .configuredKeyInvalid: "API Key 无效"
        case .missingKey: "请先配置 API Key"
        case .rateLimited: "请求过于频繁，请稍后再试"
        case .offline: "当前网络不可用"
        case .timeout: "请求超时"
        case .serverError: "CoinGecko 暂时不可用"
        case .refreshFailed: "行情更新失败"
        }
    }

    var isAcknowledgable: Bool {
        self == .corruptedStore || self == .classificationUnavailable
    }
}

struct StatusBannerPresentation: Equatable, Sendable {
    let condition: StatusCondition
    let message: String
    let isAcknowledgable: Bool
}

struct StatusSelector: Sendable {
    private(set) var active: Set<StatusCondition> = []

    var presentation: StatusBannerPresentation? {
        guard let condition = active.max(by: { $0.priority < $1.priority }) else { return nil }
        return StatusBannerPresentation(
            condition: condition,
            message: condition.message,
            isAcknowledgable: condition.isAcknowledgable
        )
    }

    mutating func activate(_ condition: StatusCondition) {
        active.insert(condition)
    }

    mutating func resolve(_ condition: StatusCondition) {
        active.remove(condition)
    }

    mutating func resolveNetworkFailures() {
        active.subtract([.offline, .timeout, .serverError, .refreshFailed])
    }
}
