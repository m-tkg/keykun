import AppKit
import KeykunCore

/// 「入力切り替え」: 左右 Command の単押しで入力ソースを切り替えるイベントハンドラ。
///
/// 判定の核は純粋ロジック `ModifierTapDetector` に委ね、本クラスは
///   - flagsChanged から左右⌘の押下/解放を device 依存ビットで判定
///   - keyDown / 他修飾の同時押しでコンボ（汚染）を通知
///   - 単押し成立時に該当サイドへ割り当てた入力ソースへ切り替え
/// を担う。イベントは消費しない（通常の⌘修飾と両立）。
@MainActor
final class InputSwitchHandler: KeyEventHandler {
    private var settings = InputSwitchSettings()
    private var detector = ModifierTapDetector(threshold: 0.3)

    /// 直近に観測した左右⌘の押下状態。
    private var leftDown = false
    private var rightDown = false

    /// device 依存フラグのビット（IOLLEvent.h）。
    private let leftCommandBit: UInt64 = 0x0000_0008   // NX_DEVICELCMDKEYMASK
    private let rightCommandBit: UInt64 = 0x0000_0010  // NX_DEVICERCMDKEYMASK

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 設定を反映する。
    func update(_ settings: InputSwitchSettings) {
        self.settings = settings
        detector.threshold = settings.tapThreshold
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard settings.isEnabled else { return false }

        if type == .keyDown {
            // ⌘保持中に通常キー → コンボ扱い（⌘C などで切替が誤発火しないように）。
            detector.contaminate()
            return false
        }

        guard type == .flagsChanged else { return false }

        let flags = event.flags
        let raw = flags.rawValue
        let newLeft = (raw & leftCommandBit) != 0
        let newRight = (raw & rightCommandBit) != 0
        let otherModifiers =
            flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskAlternate)

        // 左⌘の押下/解放を処理。
        if newLeft != leftDown {
            if newLeft {
                detector.commandDown(side: .left, otherModifiersHeld: rightDown || otherModifiers, now: now)
            } else if let side = detector.commandUp(side: .left, now: now) {
                fire(side)
            }
            leftDown = newLeft
        }

        // 右⌘の押下/解放を処理。
        if newRight != rightDown {
            if newRight {
                detector.commandDown(side: .right, otherModifiersHeld: leftDown || otherModifiers, now: now)
            } else if let side = detector.commandUp(side: .right, now: now) {
                fire(side)
            }
            rightDown = newRight
        }

        // ⌘保持中に他の修飾キーが加わったらコンボ扱い。
        if otherModifiers {
            detector.contaminate()
        }

        return false
    }

    private func fire(_ side: ModifierSide) {
        guard let id = settings.sourceID(for: side) else { return }
        InputSourceService.select(id: id)
    }
}
