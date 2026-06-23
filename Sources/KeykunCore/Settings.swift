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

/// 「入力切り替え」機能の設定。左右 Command の単押しに、それぞれ入力ソースを割り当てる。
public struct InputSwitchSettings: Codable, Equatable {
    /// 機能の有効/無効。
    public var isEnabled: Bool
    /// 左 Command 単押しで切り替える入力ソース ID（未割り当ては nil）。
    public var leftCommandSourceID: String?
    /// 右 Command 単押しで切り替える入力ソース ID（未割り当ては nil）。
    public var rightCommandSourceID: String?
    /// 単押しとみなす最大押下時間（秒）。
    public var tapThreshold: TimeInterval

    public init(
        isEnabled: Bool = false,
        leftCommandSourceID: String? = nil,
        rightCommandSourceID: String? = nil,
        tapThreshold: TimeInterval = 0.3
    ) {
        self.isEnabled = isEnabled
        self.leftCommandSourceID = leftCommandSourceID
        self.rightCommandSourceID = rightCommandSourceID
        self.tapThreshold = tapThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case leftCommandSourceID
        case rightCommandSourceID
        case tapThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InputSwitchSettings()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? defaults.isEnabled
        self.leftCommandSourceID = try container.decodeIfPresent(String.self, forKey: .leftCommandSourceID)
        self.rightCommandSourceID = try container.decodeIfPresent(String.self, forKey: .rightCommandSourceID)
        self.tapThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .tapThreshold)
            ?? defaults.tapThreshold
    }

    /// 指定サイドに割り当てられた入力ソース ID。
    public func sourceID(for side: ModifierSide) -> String? {
        switch side {
        case .left: return leftCommandSourceID
        case .right: return rightCommandSourceID
        }
    }
}
