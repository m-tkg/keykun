import XCTest
@testable import KeykunCore

final class ModifierKeyDoublePressDeciderTests: XCTestCase {
    private let lcmd = ModifierKey(modifier: .command, side: .left)
    private let rcmd = ModifierKey(modifier: .command, side: .right)
    private let ropt = ModifierKey(modifier: .option, side: .right)

    func testFirstTapArms() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        XCTAssertEqual(d.tap(key: lcmd, now: 0), .armed(lcmd))
    }

    func testSecondTapSameKeyWithinIntervalFires() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: lcmd, now: 0)
        XCTAssertEqual(d.tap(key: lcmd, now: 0.3), .fired(lcmd))
    }

    func testSecondTapAtExactIntervalFires() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: ropt, now: 0)
        XCTAssertEqual(d.tap(key: ropt, now: 0.4), .fired(ropt))
    }

    func testSecondTapAfterIntervalRearms() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: lcmd, now: 0)
        XCTAssertEqual(d.tap(key: lcmd, now: 0.5), .armed(lcmd))
    }

    func testDifferentKeyDoesNotFireAndRearms() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: lcmd, now: 0)
        // 左⌘の次に右⌘（別キー）→ 発火せず張り替え。
        XCTAssertEqual(d.tap(key: rcmd, now: 0.1), .armed(rcmd))
        // 続けて右⌘ → 右⌘の2回目として発火。
        XCTAssertEqual(d.tap(key: rcmd, now: 0.2), .fired(rcmd))
    }

    func testDifferentModifierSameSideDoesNotFire() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        let lopt = ModifierKey(modifier: .option, side: .left)
        _ = d.tap(key: lcmd, now: 0)
        // 同じ左でも種別が違えば別キー扱い。
        XCTAssertEqual(d.tap(key: lopt, now: 0.1), .armed(lopt))
    }

    func testThirdTapRequiresTwoTapsAgain() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: lcmd, now: 0)
        _ = d.tap(key: lcmd, now: 0.2)
        XCTAssertEqual(d.tap(key: lcmd, now: 0.3), .armed(lcmd))
    }

    func testResetClearsArmedState() {
        var d = ModifierKeyDoublePressDecider(interval: 0.4)
        _ = d.tap(key: lcmd, now: 0)
        d.reset()
        XCTAssertEqual(d.tap(key: lcmd, now: 0.1), .armed(lcmd))
    }
}
