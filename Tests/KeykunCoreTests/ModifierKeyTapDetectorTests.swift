import XCTest
@testable import KeykunCore

final class ModifierKeyTapDetectorTests: XCTestCase {
    private let lcmd = ModifierKey(modifier: .command, side: .left)
    private let ropt = ModifierKey(modifier: .option, side: .right)

    func testSoloTapWithinThresholdFires() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: false, now: 0)
        XCTAssertEqual(d.keyUp(lcmd, now: 0.1), lcmd)
    }

    func testLongPressDoesNotFire() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: false, now: 0)
        XCTAssertNil(d.keyUp(lcmd, now: 0.5))
    }

    func testContaminationByOtherKeyPreventsFire() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: false, now: 0)
        d.contaminate()
        XCTAssertNil(d.keyUp(lcmd, now: 0.1))
    }

    func testOtherModifierHeldAtDownPreventsFire() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: true, now: 0)
        XCTAssertNil(d.keyUp(lcmd, now: 0.1))
    }

    func testDifferentKeyUpKeepsCandidate() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: false, now: 0)
        // 別キーの解放は無視（候補は保持）。
        XCTAssertNil(d.keyUp(ropt, now: 0.05))
        // 元キーの解放で発火する。
        XCTAssertEqual(d.keyUp(lcmd, now: 0.1), lcmd)
    }

    func testResetClearsCandidate() {
        var d = ModifierKeyTapDetector(threshold: 0.3)
        d.keyDown(lcmd, otherModifiersHeld: false, now: 0)
        d.reset()
        XCTAssertNil(d.keyUp(lcmd, now: 0.1))
    }
}
