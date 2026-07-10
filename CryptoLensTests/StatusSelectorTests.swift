import XCTest
@testable import CryptoLens

final class StatusSelectorTests: XCTestCase {
    func testHighestPriorityConditionIsProjectedAndLowerOneReturnsAfterResolve() {
        var selector = StatusSelector()
        selector.activate(.offline)
        selector.activate(.missingKey)
        selector.activate(.persistenceFailure)

        XCTAssertEqual(selector.presentation?.condition, .persistenceFailure)
        selector.resolve(.persistenceFailure)
        XCTAssertEqual(selector.presentation?.condition, .missingKey)
        selector.resolve(.missingKey)
        XCTAssertEqual(selector.presentation?.condition, .offline)
    }

    func testOnlyRecoveryEventsAreAcknowledgable() {
        XCTAssertTrue(StatusCondition.corruptedStore.isAcknowledgable)
        XCTAssertTrue(StatusCondition.classificationUnavailable.isAcknowledgable)
        XCTAssertFalse(StatusCondition.missingKey.isAcknowledgable)
        XCTAssertFalse(StatusCondition.offline.isAcknowledgable)
    }
}
