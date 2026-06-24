import Foundation

/// 「同じ物理修飾キー（`ModifierKey`）を2回続けて単押ししたか」を判定する純粋ロジック。
///
/// `ModifierKeyTapDetector` が返した単押し成立キーを入力に、同一キーの猶予時間（`interval`）内の
/// 2回目で発火する。別キーが来たら発火せず、そのキーの1回目として張り替える
/// （例: 左⌘1回 → 右⌘1回 では発火しない）。
/// CGEventTap / AppKit に依存しないため単体テスト可能。時刻は呼び出し側から注入する。
public struct ModifierKeyDoublePressDecider {
    /// 判定結果。
    public enum Decision: Equatable {
        /// 1回目を受け付け、2回目を待つ。
        case armed(ModifierKey)
        /// 猶予時間内の同一キー2回目。アクション（アプリ起動）を実行する。
        case fired(ModifierKey)
    }

    /// 2回目を受け付ける猶予時間（秒）。
    public var interval: TimeInterval

    /// 直近で1回目を受け付けたキーと時刻。待機していなければ nil。
    private var armedKey: ModifierKey?
    private var armedAt: TimeInterval?

    public init(interval: TimeInterval = 0.4) {
        self.interval = interval
    }

    /// 単押しが成立したときに呼ぶ。
    public mutating func tap(key: ModifierKey, now: TimeInterval) -> Decision {
        if armedKey == key, let armedAt, now - armedAt <= interval {
            // 同じキーの猶予時間内2回目 → 発火して待機解除。
            self.armedKey = nil
            self.armedAt = nil
            return .fired(key)
        }
        // 1回目、別キー、または猶予を過ぎた打鍵 → そのキーの1回目として待機。
        armedKey = key
        armedAt = now
        return .armed(key)
    }

    /// 待機状態を解除する（タイムアウトや無効化のとき）。
    public mutating func reset() {
        armedKey = nil
        armedAt = nil
    }
}
