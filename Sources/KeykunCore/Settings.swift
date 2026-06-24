import Foundation

/// アプリ全体の設定。機能ごとにサブ構造体を持ち、機能追加時はここにプロパティを足して拡張する。
///
/// 前方/後方互換のため Codable は欠損キーを既定値で補完する（古い/新しい設定ファイルでも壊れない）。
public struct Settings: Codable, Equatable {
    /// 「安全な Quit」（⌘Q 二度押し）機能の設定。
    public var safeQuit: SafeQuitSettings
    /// 「入力切り替え」（左右⌘単押し）機能の設定。
    public var inputSwitch: InputSwitchSettings

    public init(
        safeQuit: SafeQuitSettings = SafeQuitSettings(),
        inputSwitch: InputSwitchSettings = InputSwitchSettings()
    ) {
        self.safeQuit = safeQuit
        self.inputSwitch = inputSwitch
    }

    /// 既定設定。
    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case safeQuit
        case inputSwitch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.safeQuit = try container.decodeIfPresent(SafeQuitSettings.self, forKey: .safeQuit)
            ?? SafeQuitSettings()
        self.inputSwitch = try container.decodeIfPresent(InputSwitchSettings.self, forKey: .inputSwitch)
            ?? InputSwitchSettings()
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
