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

    public init(
        safeQuit: SafeQuitSettings = SafeQuitSettings(),
        inputSwitch: InputSwitchSettings = InputSwitchSettings(),
        modifierDoublePress: ModifierDoublePressSettings = ModifierDoublePressSettings()
    ) {
        self.safeQuit = safeQuit
        self.inputSwitch = inputSwitch
        self.modifierDoublePress = modifierDoublePress
    }

    /// 既定設定。
    public static let `default` = Settings()

    /// 入力切替（⌘単押し）と修飾キー二度押し起動が同じ⌘で競合しているか。
    ///
    /// 入力切替は⌘固定のため、二度押し起動も⌘を対象にして両方有効だと同じキーを取り合う。
    /// この状態は設定 UI 側で保存を防ぐ（どちらか一方のみ有効にできる）。
    public var hasModifierConflict: Bool {
        inputSwitch.isEnabled
            && modifierDoublePress.isEnabled
            && modifierDoublePress.usesCommand
    }

    private enum CodingKeys: String, CodingKey {
        case safeQuit
        case inputSwitch
        case modifierDoublePress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.safeQuit = try container.decodeIfPresent(SafeQuitSettings.self, forKey: .safeQuit)
            ?? SafeQuitSettings()
        self.inputSwitch = try container.decodeIfPresent(InputSwitchSettings.self, forKey: .inputSwitch)
            ?? InputSwitchSettings()
        self.modifierDoublePress = try container.decodeIfPresent(ModifierDoublePressSettings.self, forKey: .modifierDoublePress)
            ?? ModifierDoublePressSettings()
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

/// 「入力切り替え」機能の設定。左右 Command の単押しに、それぞれ送出キー（英数/かな）を割り当てる。
public struct InputSwitchSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool
    /// 左 Command 単押しで送出するキー。
    public var leftCommandAction: InputSwitchAction
    /// 右 Command 単押しで送出するキー。
    public var rightCommandAction: InputSwitchAction
    /// 単押しとみなす最大押下時間（秒）。
    public var tapThreshold: TimeInterval

    public init(
        isEnabled: Bool = false,
        leftCommandAction: InputSwitchAction = .eisu,
        rightCommandAction: InputSwitchAction = .kana,
        tapThreshold: TimeInterval = 0.5
    ) {
        self.isEnabled = isEnabled
        self.leftCommandAction = leftCommandAction
        self.rightCommandAction = rightCommandAction
        self.tapThreshold = tapThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case leftCommandAction
        case rightCommandAction
        case tapThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InputSwitchSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        self.leftCommandAction = try container.decodeIfPresent(InputSwitchAction.self, forKey: .leftCommandAction)
            ?? defaults.leftCommandAction
        self.rightCommandAction = try container.decodeIfPresent(InputSwitchAction.self, forKey: .rightCommandAction)
            ?? defaults.rightCommandAction
        self.tapThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .tapThreshold)
            ?? defaults.tapThreshold
    }

    /// 指定サイドに割り当てられた送出キー。
    public func action(for side: ModifierSide) -> InputSwitchAction {
        switch side {
        case .left: return leftCommandAction
        case .right: return rightCommandAction
        }
    }
}

/// 二度押しの対象とする修飾キーの種別。
/// 左右の判別に使う device 依存フラグビット（IOLLEvent.h の NX_DEVICE*KEYMASK）を持つ。
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

/// 「特定の物理修飾キーの二度押し → アプリ起動」を1件表す割り当て。
public struct ModifierLaunchBinding: Codable, Equatable, Identifiable {
    /// SwiftUI のリスト識別用 ID（永続化もされる）。
    public var id: UUID
    /// 対象の修飾キー種別。
    public var modifier: TargetModifier
    /// 対象の左右。
    public var side: ModifierSide
    /// 起動するアプリ。
    public var app: AppTarget

    public init(
        id: UUID = UUID(),
        modifier: TargetModifier = .command,
        side: ModifierSide = .left,
        app: AppTarget = AppTarget()
    ) {
        self.id = id
        self.modifier = modifier
        self.side = side
        self.app = app
    }

    /// 検知に使う物理キー。
    public var key: ModifierKey { ModifierKey(modifier: modifier, side: side) }

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
        self.side = try container.decodeIfPresent(ModifierSide.self, forKey: .side)
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
        bindings.first { $0.key == key && $0.app.isAssigned }?.app
    }

    /// いずれかの割り当てが ⌘ を対象にしているか（入力切替との衝突判定に使う）。
    public var usesCommand: Bool {
        bindings.contains { $0.modifier == .command }
    }
}
