import XCTest
@testable import CryptoLens

final class StatusSelectorTests: XCTestCase {
    func testHighestPriorityConditionIsProjectedAndLowerOneReturnsAfterResolve() {
        var selector = StatusSelector()
        selector.activate(.offline)
        selector.activate(.configuredKeyInvalid)
        selector.activate(.persistenceFailure)

        XCTAssertEqual(selector.presentation?.condition, .persistenceFailure)
        selector.resolve(.persistenceFailure)
        XCTAssertEqual(selector.presentation?.condition, .configuredKeyInvalid)
        selector.resolve(.configuredKeyInvalid)
        XCTAssertEqual(selector.presentation?.condition, .offline)
    }

    func testOnlyRecoveryEventsAreAcknowledgable() {
        XCTAssertTrue(StatusCondition.corruptedStore.isAcknowledgable)
        XCTAssertTrue(StatusCondition.classificationUnavailable.isAcknowledgable)
        XCTAssertFalse(StatusCondition.configuredKeyInvalid.isAcknowledgable)
        XCTAssertFalse(StatusCondition.offline.isAcknowledgable)
    }
}
