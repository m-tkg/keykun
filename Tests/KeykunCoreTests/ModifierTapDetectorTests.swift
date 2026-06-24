import XCTest
@testable import KeykunCore

final class ModifierTapDetectorTests: XCTestCase {
    func testSoloLeftTapWithinThresholdFires() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        XCTAssertEqual(d.commandUp(side: .left, now: 0.1), .left)
    }

    func testSoloRightTapWithinThresholdFires() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .right, otherModifiersHeld: false, now: 0)
        XCTAssertEqual(d.commandUp(side: .right, now: 0.2), .right)
    }

    func testLongPressDoesNotFire() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        // しきい時間を超えた長押し → 発火しない
        XCTAssertNil(d.commandUp(side: .left, now: 0.5))
    }

    func testContaminationByOtherKeyPreventsFire() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        // 押下中に通常キーが押された（⌘C など）→ コンボ扱いで発火しない
        d.contaminate()
        XCTAssertNil(d.commandUp(side: .left, now: 0.1))
    }

    func testOtherModifierHeldAtDownPreventsFire() {
        var d = ModifierTapDetector(threshold: 0.3)
        // ⌘押下時点で既に shift 等が押されている → コンボ
        d.commandDown(side: .left, otherModifiersHeld: true, now: 0)
        XCTAssertNil(d.commandUp(side: .left, now: 0.1))
    }

    func testBothCommandsHeldFiresNeither() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        // 左を保持したまま右も押す → 反対側が押されているのでコンボ
        d.commandDown(side: .right, otherModifiersHeld: true, now: 0.05)
        XCTAssertNil(d.commandUp(side: .left, now: 0.1))
        XCTAssertNil(d.commandUp(side: .right, now: 0.15))
    }

    func testReleaseOfNonCandidateSideReturnsNil() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        // 候補は左。右の解放イベントが来ても何も起きない
        XCTAssertNil(d.commandUp(side: .right, now: 0.1))
        // 左を正しく離せば発火する
        XCTAssertEqual(d.commandUp(side: .left, now: 0.15), .left)
    }

    func testResetClearsCandidateSoReleaseDoesNotFire() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        // 取りこぼし相当でリセット → 押下中の候補が消え、解放しても発火しない
        d.reset()
        XCTAssertNil(d.commandUp(side: .left, now: 0.1))
        // リセット後の新しい単押しは正常に発火する
        d.commandDown(side: .right, otherModifiersHeld: false, now: 1.0)
        XCTAssertEqual(d.commandUp(side: .right, now: 1.1), .right)
    }

    func testConsecutiveSoloTapsEachFire() {
        var d = ModifierTapDetector(threshold: 0.3)
        d.commandDown(side: .left, otherModifiersHeld: false, now: 0)
        XCTAssertEqual(d.commandUp(side: .left, now: 0.1), .left)
        d.commandDown(side: .right, otherModifiersHeld: false, now: 1.0)
        XCTAssertEqual(d.commandUp(side: .right, now: 1.1), .right)
    }
}
