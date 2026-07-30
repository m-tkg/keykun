import XCTest
@testable import KeykunCore

final class ModifierFlagsInterpreterTests: XCTestCase {
    private let lctl = ModifierKey(modifier: .control, side: .left)
    private let rctl = ModifierKey(modifier: .control, side: .right)

    // generic mask（device 非依存）
    private let maskControl: UInt64 = 0x0004_0000
    private let maskShift: UInt64 = 0x0002_0000
    private let maskAlternate: UInt64 = 0x0008_0000
    private let maskCommand: UInt64 = 0x0010_0000
    private let maskAlphaShift: UInt64 = 0x0001_0000

    // device 依存ビット
    private let bitLCtl: UInt64 = 0x0000_0001
    private let bitRCtl: UInt64 = 0x0000_2000

    // MARK: - 物理キー（device ビットあり・既存動作の保全）

    func testLeftControlDownUpWithDeviceBit() {
        var i = ModifierFlagsInterpreter()
        let down = i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl)
        XCTAssertEqual(down.transition, .down(lctl))
        let up = i.interpret(keyCode: 59, rawFlags: 0)
        XCTAssertEqual(up.transition, .up(lctl))
    }

    func testRightControlDownUpWithDeviceBit() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 62, rawFlags: maskControl | bitRCtl).transition, .down(rctl))
        XCTAssertEqual(i.interpret(keyCode: 62, rawFlags: 0).transition, .up(rctl))
    }

    func testAllPhysicalModifierKeysDownUp() {
        // keyCode / 種別 / 左右 / device ビット / generic mask の一巡。
        let cases: [(Int64, ModifierKey, UInt64, UInt64)] = [
            (55, ModifierKey(modifier: .command, side: .left), 0x8, maskCommand),
            (54, ModifierKey(modifier: .command, side: .right), 0x10, maskCommand),
            (56, ModifierKey(modifier: .shift, side: .left), 0x2, maskShift),
            (60, ModifierKey(modifier: .shift, side: .right), 0x4, maskShift),
            (58, ModifierKey(modifier: .option, side: .left), 0x20, maskAlternate),
            (61, ModifierKey(modifier: .option, side: .right), 0x40, maskAlternate),
        ]
        for (keyCode, key, bit, mask) in cases {
            var i = ModifierFlagsInterpreter()
            XCTAssertEqual(i.interpret(keyCode: keyCode, rawFlags: mask | bit).transition, .down(key))
            XCTAssertEqual(i.interpret(keyCode: keyCode, rawFlags: 0).transition, .up(key))
        }
    }

    func testBothControlsHeldReleaseOneByOne() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl).transition, .down(lctl))
        XCTAssertEqual(
            i.interpret(keyCode: 62, rawFlags: maskControl | bitLCtl | bitRCtl).transition, .down(rctl))
        // 左解放: 左ビット消失・generic mask は右で残存 → トグルで up(左)。
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl | bitRCtl).transition, .up(lctl))
        XCTAssertEqual(i.interpret(keyCode: 62, rawFlags: 0).transition, .up(rctl))
    }

    func testDeviceBitPresentWhileTrackedDownProducesNoTransition() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl).transition, .down(lctl))
        // 追跡 down 中の bit 付き down 再来（重複イベント）→ 遷移なし。
        XCTAssertNil(i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl).transition)
    }

    // MARK: - リマップ環境（device ビットが立たない）

    func testRemappedControlKeyCode59WithoutDeviceBit() {
        var i = ModifierFlagsInterpreter()
        // 押下: mask あり・device ビットなし → トグルで down。
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl).transition, .down(lctl))
        // 解放: mask 消失 → up。
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: 0).transition, .up(lctl))
    }

    func testCapsLockKeyCode57AsControl() {
        var i = ModifierFlagsInterpreter()
        // control mask が新たに立った → 左 control の down。
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: maskControl).transition, .down(lctl))
        // 押下中の次の keyCode 57 → up。
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: 0).transition, .up(lctl))
    }

    func testCapsLockAsControlUpWhilePhysicalControlHeld() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: maskControl).transition, .down(lctl))
        // 物理右⌃を追加押下。
        XCTAssertEqual(
            i.interpret(keyCode: 62, rawFlags: maskControl | bitRCtl).transition, .down(rctl))
        // caps 解放: control mask は物理⌃で残存しても up(左⌃) になる。
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: maskControl | bitRCtl).transition, .up(lctl))
    }

    func testNormalCapsLockToggleIgnored() {
        var i = ModifierFlagsInterpreter()
        let on = i.interpret(keyCode: 57, rawFlags: maskAlphaShift)
        XCTAssertNil(on.transition)
        XCTAssertFalse(on.otherModifiersHeld)
        XCTAssertFalse(on.multipleModifiersHeld)
        let off = i.interpret(keyCode: 57, rawFlags: 0)
        XCTAssertNil(off.transition)
    }

    func testNormalCapsLockWhilePhysicalControlHeldNotMisinterpreted() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl).transition, .down(lctl))
        // 物理⌃保持中（control mask 既存）の通常 caps 打鍵 → control down と誤解釈しない。
        XCTAssertNil(
            i.interpret(keyCode: 57, rawFlags: maskControl | maskAlphaShift | bitLCtl).transition)
    }

    // MARK: - 汚染（コンボ）判定

    func testOtherModifiersHeldOnDownWithGenericMaskOnly() {
        var i = ModifierFlagsInterpreter()
        // shift は device ビットなしで generic mask のみ立っている。
        let r = i.interpret(keyCode: 59, rawFlags: maskControl | maskShift | bitLCtl)
        XCTAssertEqual(r.transition, .down(lctl))
        XCTAssertTrue(r.otherModifiersHeld)
    }

    func testSiblingSameTypeHeldCountsAsOther() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 59, rawFlags: maskControl | bitLCtl).transition, .down(lctl))
        let r = i.interpret(keyCode: 62, rawFlags: maskControl | bitLCtl | bitRCtl)
        XCTAssertEqual(r.transition, .down(rctl))
        // 同種別の反対側（左⌃）が押下中 → otherModifiersHeld。
        XCTAssertTrue(r.otherModifiersHeld)
    }

    func testMultipleModifiersHeldWithTwoMaskTypes() {
        var i = ModifierFlagsInterpreter()
        let r = i.interpret(keyCode: 56, rawFlags: maskControl | maskShift | bitLCtl | 0x2)
        XCTAssertTrue(r.multipleModifiersHeld)
    }

    func testAlphaShiftDoesNotCountAsModifier() {
        var i = ModifierFlagsInterpreter()
        let r = i.interpret(keyCode: 59, rawFlags: maskControl | maskAlphaShift | bitLCtl)
        XCTAssertEqual(r.transition, .down(lctl))
        XCTAssertFalse(r.otherModifiersHeld)
        XCTAssertFalse(r.multipleModifiersHeld)
    }

    func testFnKeyCodeProducesNoTransition() {
        var i = ModifierFlagsInterpreter()
        XCTAssertNil(i.interpret(keyCode: 63, rawFlags: 0x80_0000).transition)
    }

    // MARK: - reset

    func testResetClearsTrackedState() {
        var i = ModifierFlagsInterpreter()
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: maskControl).transition, .down(lctl))
        i.reset()
        // reset 後は caps down フラグも previous mask もクリアされ、初回イベントが正しく解釈される。
        XCTAssertEqual(i.interpret(keyCode: 57, rawFlags: maskControl).transition, .down(lctl))
    }

    // MARK: - 統合（interpreter + detector + decider）

    func testRemappedCapsLockDoubleTapFires() {
        var interpreter = ModifierFlagsInterpreter()
        var detector = ModifierKeyTapDetector(threshold: 0.3)
        var decider = ModifierKeyDoublePressDecider(interval: 0.3)

        var fired: ModifierKey?
        // リマップ環境のイベント列（device ビットなし）: down→up→down→up。
        let events: [(Int64, UInt64, TimeInterval)] = [
            (57, maskControl, 0.00),
            (57, 0, 0.05),
            (57, maskControl, 0.20),
            (57, 0, 0.25),
        ]
        for (keyCode, flags, now) in events {
            let r = interpreter.interpret(keyCode: keyCode, rawFlags: flags)
            switch r.transition {
            case .down(let key):
                detector.keyDown(key, otherModifiersHeld: r.otherModifiersHeld, now: now)
            case .up(let key):
                if let tap = detector.keyUp(key, now: now),
                   case .fired(let firedKey) = decider.tap(key: tap, now: now) {
                    fired = firedKey
                }
            case nil:
                break
            }
            if r.multipleModifiersHeld { detector.contaminate() }
        }
        XCTAssertEqual(fired, lctl)
    }

    func testRemappedControlComboDoesNotFire() {
        var interpreter = ModifierFlagsInterpreter()
        var detector = ModifierKeyTapDetector(threshold: 0.3)
        var decider = ModifierKeyDoublePressDecider(interval: 0.3)

        var fired: ModifierKey?
        // ⌃C 相当: down → 通常キー（contaminate）→ up、を2回。
        for base in [0.0, 0.2] {
            let down = interpreter.interpret(keyCode: 57, rawFlags: maskControl)
            if case .down(let key) = down.transition {
                detector.keyDown(key, otherModifiersHeld: down.otherModifiersHeld, now: base)
            }
            detector.contaminate()  // ハンドラの keyDown イベント経路に相当。
            let up = interpreter.interpret(keyCode: 57, rawFlags: 0)
            if case .up(let key) = up.transition,
               let tap = detector.keyUp(key, now: base + 0.05),
               case .fired(let firedKey) = decider.tap(key: tap, now: base + 0.05) {
                fired = firedKey
            }
        }
        XCTAssertNil(fired)
    }
}
