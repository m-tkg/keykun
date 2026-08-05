import Foundation

/// アプリ全体の設定。機能ごとにサブ構造体を持ち、機能追加時はここにプロパティを足して拡張する。
///
/// 前方/後方互換のため Codable は欠損キーを既定値で補完する（古い/新しい設定ファイルでも壊れない）。
public struct Settings: Codable, Equatable {
    /// 「安全な Quit」（⌘Q 二度押し）機能の設定。
    public var safeQuit: SafeQuitSettings
    /// 「入力切り替え」（左右⌘単押し）機能の設定。
    public var inputSwitch: InputSwitchSettings
    /// 「修飾キー二度押しでアプリ起動」機能の設定。
    public var modifierDoublePress: ModifierDoublePressSettings
    /// 「Slack の Esc を SKK キャンセルへ変換」機能の設定。
    public var slackEscape: SlackEscapeSettings

    public init(
        safeQuit: SafeQuitSettings = SafeQuitSettings(),
        inputSwitch: InputSwitchSettings = InputSwitchSettings(),
        modifierDoublePress: ModifierDoublePressSettings = ModifierDoublePressSettings(),
        slackEscape: SlackEscapeSettings = SlackEscapeSettings()
    ) {
        self.safeQuit = safeQuit
        self.inputSwitch = inputSwitch
        self.modifierDoublePress = modifierDoublePress
        self.slackEscape = slackEscape
    }

    /// 既定設定。
    public static let `default` = Settings()

    /// 入力切替と修飾キー二度押し起動が同じ修飾キーで競合しているか。
    ///
    /// 入力切替の対象修飾キーと二度押し起動が同じキー種別を使い、両方有効だと取り合う。
    /// この状態は設定 UI 側で保存を防ぐ（どちらか一方のみ有効にできる）。
    public var hasModifierConflict: Bool {
        inputSwitch.isEnabled
            && modifierDoublePress.isEnabled
            && modifierDoublePress.bindings.contains { $0.modifier == inputSwitch.targetModifier }
    }

    private enum CodingKeys: String, CodingKey {
        case safeQuit
        case inputSwitch
        case modifierDoublePress
        case slackEscape
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.safeQuit = try container.decodeIfPresent(SafeQuitSettings.self, forKey: .safeQuit)
            ?? SafeQuitSettings()
        self.inputSwitch = try container.decodeIfPresent(InputSwitchSettings.self, forKey: .inputSwitch)
            ?? InputSwitchSettings()
        self.modifierDoublePress = try container.decodeIfPresent(ModifierDoublePressSettings.self, forKey: .modifierDoublePress)
            ?? ModifierDoublePressSettings()
        self.slackEscape = try container.decodeIfPresent(SlackEscapeSettings.self, forKey: .slackEscape)
            ?? SlackEscapeSettings()
    }
}

/// 「安全な Quit」機能の設定。
public struct SafeQuitSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool
    /// ⌘Q の2回目を受け付ける猶予時間（秒）。
    public var interval: TimeInterval

    public init(isEnabled: Bool = true, interval: TimeInterval = 1.0) {
        self.isEnabled = isEnabled
        self.interval = interval
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SafeQuitSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        self.interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval)
            ?? defaults.interval
    }
}

/// 左右 Command 単押し時に送出するキー（Karabiner 方式）。
/// 入力ソース選択ではなく、英数/かなキーの信号を送って IME のモードを切り替える。
public enum InputSwitchAction: String, Codable, Equatable, CaseIterable {
    /// 何もしない。
    case none
    /// 「英数」キー（英語入力へ）。
    case eisu
    /// 「かな」キー（日本語入力へ）。
    case kana
}

/// 「入力切り替え」機能の設定。左右修飾キーの単押しに、それぞれ送出キー（英数/かな）を割り当てる。
public struct InputSwitchSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool
    /// 単押しを検知する修飾キーの種別。
    public var targetModifier: TargetModifier
    /// 左側単押しで送出するキー。
    public var leftAction: InputSwitchAction
    /// 右側単押しで送出するキー。
    public var rightAction: InputSwitchAction
    /// 単押しとみなす最大押下時間（秒）。
    public var tapThreshold: TimeInterval

    public init(
        isEnabled: Bool = false,
        targetModifier: TargetModifier = .option,
        leftAction: InputSwitchAction = .eisu,
        rightAction: InputSwitchAction = .kana,
        tapThreshold: TimeInterval = 0.5
    ) {
        self.isEnabled = isEnabled
        self.targetModifier = targetModifier
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.tapThreshold = tapThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case targetModifier
        case leftAction
        case rightAction
        case tapThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InputSwitchSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        self.targetModifier = try container.decodeIfPresent(TargetModifier.self, forKey: .targetModifier)
            ?? defaults.targetModifier
        self.leftAction = try container.decodeIfPresent(InputSwitchAction.self, forKey: .leftAction)
            ?? defaults.leftAction
        self.rightAction = try container.decodeIfPresent(InputSwitchAction.self, forKey: .rightAction)
            ?? defaults.rightAction
        self.tapThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .tapThreshold)
            ?? defaults.tapThreshold
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(targetModifier, forKey: .targetModifier)
        try container.encode(leftAction, forKey: .leftAction)
        try container.encode(rightAction, forKey: .rightAction)
        try container.encode(tapThreshold, forKey: .tapThreshold)
    }

    /// 指定サイドに割り当てられた送出キー。
    public func action(for side: ModifierSide) -> InputSwitchAction {
        switch side {
        case .left: return leftAction
        case .right: return rightAction
        }
    }
}

/// 二度押しの対象とする修飾キーの種別。
/// 左右の判別に使う device 依存フラグビット（IOLLEvent.h の NX_DEVICE*KEYMASK）を持つ。
///
/// device ビットは非公式で、Caps Lock→Control リマップ環境等では立たないことがあるため、
/// 単独では押下判定に使わない（keyCode を一次情報とする `ModifierFlagsInterpreter` を参照）。
public enum TargetModifier: String, Codable, Equatable, CaseIterable {
    case command
    case option
    case control
    case shift

    /// 左側キーの device 依存フラグビット。
    public var leftBit: UInt64 {
        switch self {
        case .command: return 0x0000_0008  // NX_DEVICELCMDKEYMASK
        case .option: return 0x0000_0020   // NX_DEVICELALTKEYMASK
        case .control: return 0x0000_0001  // NX_DEVICELCTLKEYMASK
        case .shift: return 0x0000_0002    // NX_DEVICELSHIFTKEYMASK
        }
    }

    /// 右側キーの device 依存フラグビット。
    public var rightBit: UInt64 {
        switch self {
        case .command: return 0x0000_0010  // NX_DEVICERCMDKEYMASK
        case .option: return 0x0000_0040   // NX_DEVICERALTKEYMASK
        case .control: return 0x0000_2000  // NX_DEVICERCTLKEYMASK
        case .shift: return 0x0000_0004    // NX_DEVICERSHIFTKEYMASK
        }
    }
}

/// 起動対象アプリ。bundle identifier が空なら未割り当て。
public struct AppTarget: Codable, Equatable {
    /// 起動するアプリの bundle identifier。空文字なら未割り当て。
    public var bundleIdentifier: String
    /// UI 表示用のアプリ名。
    public var displayName: String

    public init(bundleIdentifier: String = "", displayName: String = "") {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    /// アプリが割り当て済みか。
    public var isAssigned: Bool { !bundleIdentifier.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppTarget()
        self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            ?? defaults.bundleIdentifier
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? defaults.displayName
    }
}

/// 二度押し検知の同一性となる物理修飾キー（種別 + 左右）。
public struct ModifierKey: Hashable, Codable {
    /// 修飾キーの種別（⌘/⌥/⌃/⇧）。
    public var modifier: TargetModifier
    /// 左右。
    public var side: ModifierSide

    public init(modifier: TargetModifier, side: ModifierSide) {
        self.modifier = modifier
        self.side = side
    }

    /// この物理キーに対応する device 依存フラグビット。
    public var deviceBit: UInt64 {
        switch side {
        case .left: return modifier.leftBit
        case .right: return modifier.rightBit
        }
    }
}

/// 割り当てが反応する左右。物理キー識別子（`ModifierSide`）と異なり「両方（どちらでも）」を持つ。
///
/// `ModifierSide` に `.both` を足すと `ModifierKey.deviceBit` が「存在しない両方ビット」を扱う羽目になるため、
/// 割り当て専用の別 enum として分離する。`.both` はハンドラに渡る前に左右2つの `ModifierKey` へ展開する。
/// raw value は旧 JSON 互換のため `ModifierSide` と一致させる（`"left"`/`"right"`）。
public enum LaunchSide: String, Codable, Equatable, CaseIterable {
    case left
    case right
    case both
}

/// 「特定の物理修飾キーの二度押し → アプリ起動」を1件表す割り当て。
public struct ModifierLaunchBinding: Codable, Equatable, Identifiable {
    /// SwiftUI のリスト識別用 ID（永続化もされる）。
    public var id: UUID
    /// 対象の修飾キー種別。
    public var modifier: TargetModifier
    /// 反応する左右（`.both` は左右どちらの二度押しでも発火）。
    public var side: LaunchSide
    /// 起動するアプリ。
    public var app: AppTarget

    public init(
        id: UUID = UUID(),
        modifier: TargetModifier = .command,
        side: LaunchSide = .left,
        app: AppTarget = AppTarget()
    ) {
        self.id = id
        self.modifier = modifier
        self.side = side
        self.app = app
    }

    /// この割り当てが指定の物理キーに反応するか。`.both` は左右どちらにも反応する。
    public func matches(_ key: ModifierKey) -> Bool {
        modifier == key.modifier && (side == .both || side.rawValue == key.side.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case modifier
        case side
        case app
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ModifierLaunchBinding()
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.modifier = try container.decodeIfPresent(TargetModifier.self, forKey: .modifier)
            ?? defaults.modifier
        self.side = try container.decodeIfPresent(LaunchSide.self, forKey: .side)
            ?? defaults.side
        self.app = try container.decodeIfPresent(AppTarget.self, forKey: .app)
            ?? defaults.app
    }
}

/// 「修飾キー二度押し」のタイミング定数。
/// 単押し判定時間・二度押し猶予時間はユーザーには分かりにくいため設定 UI からは外し、ここで固定する。
public enum ModifierDoublePressTiming {
    /// 単押しとみなす最大押下時間（秒）。
    public static let tapThreshold: TimeInterval = 0.3
    /// 二度押しの2回目を受け付ける猶予時間（秒）。
    public static let interval: TimeInterval = 0.3
}

/// 「修飾キー二度押しでアプリ起動」機能の設定。
/// 任意の (修飾キー種別, 左右) に対してアプリを割り当てる複数の割り当てを持つ。
///
/// 単押し判定時間・二度押し猶予時間は分かりにくいため UI からは外し、`ModifierDoublePressTiming` で固定する。
public struct ModifierDoublePressSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool
    /// 各物理キーへのアプリ割り当て。
    public var bindings: [ModifierLaunchBinding]

    public init(
        isEnabled: Bool = false,
        bindings: [ModifierLaunchBinding] = []
    ) {
        self.isEnabled = isEnabled
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case bindings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ModifierDoublePressSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        self.bindings = try container.decodeIfPresent([ModifierLaunchBinding].self, forKey: .bindings)
            ?? defaults.bindings
    }

    /// 指定した物理キーに割り当てられた、アプリが設定済みの起動対象。無ければ nil。
    public func app(for key: ModifierKey) -> AppTarget? {
        bindings.first { $0.matches(key) && $0.app.isAssigned }?.app
    }

    /// 監視対象（アプリ割り当て済み）の物理キー一覧。`.both` は左右 2 キーへ展開し、重複は除く。
    public var watchedKeys: [ModifierKey] {
        var seen = Set<ModifierKey>()
        var result: [ModifierKey] = []
        for binding in bindings where binding.app.isAssigned {
            let sides: [ModifierSide]
            switch binding.side {
            case .left: sides = [.left]
            case .right: sides = [.right]
            case .both: sides = [.left, .right]
            }
            for side in sides {
                let key = ModifierKey(modifier: binding.modifier, side: side)
                if seen.insert(key).inserted { result.append(key) }
            }
        }
        return result
    }

}

/// Slack が最前面のときだけ Esc を Ctrl-G に置き換える設定。
///
/// SKK 系 IME では Ctrl-G がキャンセル操作として使われるため、Slack 側の Esc ショートカットを発火させずに
/// SKK のキャンセル操作だけを成立させるための回避策として使う。
public struct SlackEscapeSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SlackEscapeSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
    }
}
