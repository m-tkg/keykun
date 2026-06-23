import XCTest
@testable import KeykunCore

final class DoublePressDeciderTests: XCTestCase {
    func testFirstPressIsConsumedAndArms() {
        var decider = DoublePressDecider(interval: 1.0)
        XCTAssertEqual(decider.handleQuitKey(now: 0), .consumeAndArm)
        XCTAssertTrue(decider.isArmed)
    }

    func testSecondPressWithinIntervalPassesThrough() {
        var decider = DoublePressDecider(interval: 1.0)
        _ = decider.handleQuitKey(now: 0)
        // 猶予時間内の2回目 → 通す
        XCTAssertEqual(decider.handleQuitKey(now: 0.5), .passThrough)
        // 通した後は待機解除されている
        XCTAssertFalse(decider.isArmed)
    }

    func testSecondPressAtExactIntervalPassesThrough() {
        var decider = DoublePressDecider(interval: 1.0)
        _ = decider.handleQuitKey(now: 0)
        // 境界（ちょうど interval）は通す
        XCTAssertEqual(decider.handleQuitKey(now: 1.0), .passThrough)
    }

    func testSecondPressAfterIntervalIsTreatedAsFirstAgain() {
        var decider = DoublePressDecider(interval: 1.0)
        _ = decider.handleQuitKey(now: 0)
        // 猶予を過ぎた2回目 → 改めて1回目扱い（握りつぶす）
        XCTAssertEqual(decider.handleQuitKey(now: 1.5), .consumeAndArm)
        XCTAssertTrue(decider.isArmed)
    }

    func testThirdPressRequiresTwoPressesAgain() {
        var decider = DoublePressDecider(interval: 1.0)
        _ = decider.handleQuitKey(now: 0)           // 1回目: 握りつぶす
        _ = decider.handleQuitKey(now: 0.3)         // 2回目: 通す（解除）
        // 続けて押しても、また1回目から始まる
        XCTAssertEqual(decider.handleQuitKey(now: 0.4), .consumeAndArm)
    }

    func testResetClearsArmedState() {
        var decider = DoublePressDecider(interval: 1.0)
        _ = decider.handleQuitKey(now: 0)
        decider.reset()
        XCTAssertFalse(decider.isArmed)
        // reset 後の押下は1回目扱い
        XCTAssertEqual(decider.handleQuitKey(now: 0.1), .consumeAndArm)
    }

    func testShorterIntervalRejectsLateSecondPress() {
        var decider = DoublePressDecider(interval: 0.5)
        _ = decider.handleQuitKey(now: 0)
        // 0.5 秒を超えた2回目 → 握りつぶす（1回目扱い）
        XCTAssertEqual(decider.handleQuitKey(now: 0.6), .consumeAndArm)
    }
}
