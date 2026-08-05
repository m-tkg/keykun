import AppKit
import KeykunCore

/// 「入力切り替え」: 左右修飾キーの単押しで英数/かなキーを送出するイベントハンドラ。
///
/// 判定の核は純粋ロジック `ModifierTapDetector` に委ね、本クラスは
///   - flagsChanged から対象修飾キーの押下/解放を device 依存ビットで判定
///   - keyDown / 他修飾の同時押しでコンボ（汚染）を通知
///   - 単押し成立時に該当サイドへ割り当てた入力ソースへ切り替え
/// を担う。イベントは消費しない（通常の修飾キー操作と両立）。
@MainActor
final class InputSwitchHandler: KeyEventHandler {
    private var settings = InputSwitchSettings()
    private var detector = ModifierTapDetector(threshold: 0.3)

    /// 直近に観測した左右の押下状態。
    private var leftDown = false
    private var rightDown = false

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 設定を反映する。
    func update(_ settings: InputSwitchSettings) {
        self.settings = settings
        detector.threshold = settings.tapThreshold
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard settings.isEnabled else { return false }

        if type == .keyDown {
            detector.contaminate()
            return false
        }

        guard type == .flagsChanged else { return false }

        let flags = event.flags
        let raw = flags.rawValue
        let target = settings.targetModifier
        let newLeft = (raw & target.leftBit) != 0
        let newRight = (raw & target.rightBit) != 0
        let otherModifiers = hasOtherModifiers(flags: flags, excluding: target)

        if newLeft != leftDown {
            if newLeft {
                detector.commandDown(side: .left, otherModifiersHeld: rightDown || otherModifiers, now: now)
            } else if let side = detector.commandUp(side: .left, now: now) {
                fire(side)
            }
            leftDown = newLeft
        }

        if newRight != rightDown {
            if newRight {
                detector.commandDown(side: .right, otherModifiersHeld: leftDown || otherModifiers, now: now)
            } else if let side = detector.commandUp(side: .right, now: now) {
                fire(side)
            }
            rightDown = newRight
        }

        if otherModifiers {
            detector.contaminate()
        }

        return false
    }

    /// 対象修飾キー以外の修飾キーが押されているか判定する。
    private func hasOtherModifiers(flags: CGEventFlags, excluding target: TargetModifier) -> Bool {
        switch target {
        case .command:
            return flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        case .option:
            return flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskCommand)
        case .control:
            return flags.contains(.maskShift) || flags.contains(.maskCommand) || flags.contains(.maskAlternate)
        case .shift:
            return flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        }
    }

    private func fire(_ side: ModifierSide) {
        let keyCode: CGKeyCode
        switch settings.action(for: side) {
        case .none: return
        case .eisu: keyCode = InputModeKey.eisu
        case .kana: keyCode = InputModeKey.kana
        }
        // イベントタップのコールバック内で再入的に post しないよう、復帰後に送出する。
        // キー送出は軽量なので main で問題ない。
        DispatchQueue.main.async {
            InputModeKey.post(keyCode)
        }
    }

    /// イベント取りこぼし（タップ無効化）後に状態が固着しないよう、観測状態をリセットする。
    func reset() {
        leftDown = false
        rightDown = false
        detector.reset()
    }
}
