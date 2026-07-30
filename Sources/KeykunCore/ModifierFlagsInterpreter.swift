import Foundation

/// flagsChanged イベント（keyCode + flags 生値）を解釈し、
/// どの物理修飾キー（`ModifierKey`）が押下/解放されたかを判定する純粋ロジック。
///
/// device 依存ビット（IOLLEvent.h の NX_DEVICE*KEYMASK）は非公式で、
/// Caps Lock→Control リマップ（システム設定/hidutil）環境ではビットが立たない flagsChanged が
/// 来ることがある。そのため keyCode（どのキーが変化したかの一次情報）を主として、
/// 「device ビット → device 非依存の総合フラグ（generic mask）→ 内部追跡状態のトグル」の
/// 3段判定で down/up を決める:
///   1. device ビットが立っている → down（物理キーの確定情報）
///   2. 当該種別の generic mask が消えている → up（種別の全キー解放が確定）
///   3. それ以外（mask あり・device ビットなし）→ 内部追跡状態のトグル
/// ルール1・2 は絶対判定なので、イベント取りこぼしで追跡状態がずれても自己修復する。
///
/// Caps Lock（keyCode 57）は特別扱い: リマップで Control として機能する場合
/// 「generic の control mask がそのイベントで新たに立った」ときのみ左 Control の down とみなし
/// （macOS の割り当て意味論に合わせる）、通常の Caps Lock トグル（alphaShift のみ）は無視する。
///
/// CGEvent に依存しないため単体テスト可能。
public struct ModifierFlagsInterpreter {
    /// 1 イベントの解釈結果。
    public struct Interpretation: Equatable {
        /// このイベントで遷移した物理キー。修飾キー以外・通常 Caps Lock 等は nil。
        public var transition: Transition?
        /// 遷移キー以外の修飾（別種別の generic mask、または同種別の反対側）が押下中か。
        /// down 時のコンボ（汚染）判定に使う。
        public var otherModifiersHeld: Bool
        /// 複数の修飾キーが押下中か。対象キー保持中への他修飾追加の汚染判定に使う。
        public var multipleModifiersHeld: Bool

        public init(
            transition: Transition? = nil,
            otherModifiersHeld: Bool = false,
            multipleModifiersHeld: Bool = false
        ) {
            self.transition = transition
            self.otherModifiersHeld = otherModifiersHeld
            self.multipleModifiersHeld = multipleModifiersHeld
        }
    }

    /// 物理修飾キーの状態遷移。
    public enum Transition: Equatable {
        case down(ModifierKey)
        case up(ModifierKey)
    }

    /// 押下中と追跡している物理キー。
    private var trackedDown: Set<ModifierKey> = []
    /// リマップされた Caps Lock を Control として押下中か。
    private var capsAsControlDown = false
    /// 直前イベントの generic mask（Caps Lock リマップの down 判定に使う）。
    private var previousGenericMasks: UInt64 = 0

    public init() {}

    /// flagsChanged 1 件を解釈し、内部追跡状態を更新する。
    /// - Parameters:
    ///   - keyCode: イベントの仮想キーコード（`.keyboardEventKeycode`）。
    ///   - rawFlags: イベントの flags 生値（`CGEventFlags.rawValue`）。
    public mutating func interpret(keyCode: Int64, rawFlags: UInt64) -> Interpretation {
        let genericNow = rawFlags & Self.allGenericMasks
        defer { previousGenericMasks = genericNow }

        let transition: Transition?
        if keyCode == Self.capsLockKeyCode {
            transition = interpretCapsLock(genericNow: genericNow)
        } else if let key = Self.key(forKeyCode: keyCode) {
            transition = interpretModifierKey(key, rawFlags: rawFlags, genericNow: genericNow)
        } else {
            // fn や未知の keyCode は遷移なし（汚染判定のみ返す）。
            transition = nil
        }

        return Interpretation(
            transition: transition,
            otherModifiersHeld: otherModifiersHeld(than: transition, genericNow: genericNow),
            multipleModifiersHeld: multipleModifiersHeld(genericNow: genericNow)
        )
    }

    /// イベント取りこぼし（タップ無効化）後の状態固着を防ぐため、追跡状態を全クリアする。
    public mutating func reset() {
        trackedDown.removeAll()
        capsAsControlDown = false
        previousGenericMasks = 0
    }

    // MARK: - 判定

    /// 通常の修飾 keyCode の 3 段判定。
    private mutating func interpretModifierKey(
        _ key: ModifierKey, rawFlags: UInt64, genericNow: UInt64
    ) -> Transition? {
        let wasDown = trackedDown.contains(key)
        let newDown: Bool
        if rawFlags & key.deviceBit != 0 {
            newDown = true
        } else if genericNow & key.modifier.genericMask == 0 {
            newDown = false
        } else {
            newDown = !wasDown
        }
        guard newDown != wasDown else { return nil }
        if newDown {
            trackedDown.insert(key)
            return .down(key)
        } else {
            trackedDown.remove(key)
            return .up(key)
        }
    }

    /// Caps Lock（keyCode 57）の特別処理。リマップされて Control として機能する場合のみ
    /// 左 Control の down/up として扱い、通常のトグル（alphaShift のみ）は無視する。
    private mutating func interpretCapsLock(genericNow: UInt64) -> Transition? {
        let leftControl = ModifierKey(modifier: .control, side: .left)
        if capsAsControlDown {
            // 押下中の Caps Lock イベントは解放（物理 Control 併用で control mask が残っていても）。
            capsAsControlDown = false
            trackedDown.remove(leftControl)
            return .up(leftControl)
        }
        let controlMask = TargetModifier.control.genericMask
        let controlAppeared =
            genericNow & controlMask != 0 && previousGenericMasks & controlMask == 0
        guard controlAppeared else { return nil }
        capsAsControlDown = true
        trackedDown.insert(leftControl)
        return .down(leftControl)
    }

    /// 遷移キー以外の修飾が押下中か（別種別の generic mask、または同種別の反対側の追跡状態）。
    private func otherModifiersHeld(than transition: Transition?, genericNow: UInt64) -> Bool {
        guard case .down(let key) = transition else { return false }
        if genericNow & ~key.modifier.genericMask != 0 { return true }
        let oppositeSide: ModifierSide = key.side == .left ? .right : .left
        let sibling = ModifierKey(modifier: key.modifier, side: oppositeSide)
        return trackedDown.contains(sibling)
    }

    /// 複数の修飾キーが押下中か（generic mask の種別数、または追跡中の押下キー数）。
    private func multipleModifiersHeld(genericNow: UInt64) -> Bool {
        let typeCount = TargetModifier.allCases.filter { genericNow & $0.genericMask != 0 }.count
        return typeCount >= 2 || trackedDown.count >= 2
    }

    // MARK: - 定数

    private static let capsLockKeyCode: Int64 = 57

    /// 4 種別の generic mask の総和（alphaShift / secondaryFn は含めない）。
    private static let allGenericMasks: UInt64 =
        TargetModifier.allCases.reduce(0) { $0 | $1.genericMask }

    /// 修飾キーの仮想キーコード（Carbon kVK_*）→ 物理キー。Caps Lock / fn は対象外。
    private static func key(forKeyCode keyCode: Int64) -> ModifierKey? {
        switch keyCode {
        case 55: return ModifierKey(modifier: .command, side: .left)   // kVK_Command
        case 54: return ModifierKey(modifier: .command, side: .right)  // kVK_RightCommand
        case 56: return ModifierKey(modifier: .shift, side: .left)     // kVK_Shift
        case 60: return ModifierKey(modifier: .shift, side: .right)    // kVK_RightShift
        case 58: return ModifierKey(modifier: .option, side: .left)    // kVK_Option
        case 61: return ModifierKey(modifier: .option, side: .right)   // kVK_RightOption
        case 59: return ModifierKey(modifier: .control, side: .left)   // kVK_Control
        case 62: return ModifierKey(modifier: .control, side: .right)  // kVK_RightControl
        default: return nil
        }
    }
}

extension TargetModifier {
    /// device 非依存の総合フラグ（CGEventFlags の maskCommand 等と同値）。
    /// KeykunCore は CoreGraphics 非依存のため生値で持つ。
    public var genericMask: UInt64 {
        switch self {
        case .command: return 0x0010_0000  // maskCommand
        case .option: return 0x0008_0000   // maskAlternate
        case .control: return 0x0004_0000  // maskControl
        case .shift: return 0x0002_0000    // maskShift
        }
    }
}
