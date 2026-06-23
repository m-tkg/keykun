import Foundation

/// 「⌘Q を2回押さないと終了させない」判定の純粋ロジック。
///
/// AppKit / CGEventTap に依存しないため単体テスト可能。
/// 時刻は呼び出し側から `now`（単調増加する秒）として注入する。
///
/// 使い方:
///   var decider = DoublePressDecider(interval: 1.0)
///   switch decider.handleQuitKey(now: clock()) {
///   case .consumeAndArm: // 1回目 → イベントを握りつぶして待機
///   case .passThrough:   // 時間内の2回目 → そのまま通す（＝終了）
///   }
public struct DoublePressDecider {
    /// ⌘Q の判定に対する応答。
    public enum Decision: Equatable {
        /// 1回目。イベントを握りつぶし、2回目を待つ。
        case consumeAndArm
        /// 時間内の2回目。イベントを通してアプリを終了させる。
        case passThrough
    }

    /// 2回目を受け付ける猶予時間（秒）。
    public var interval: TimeInterval

    /// 直近で1回目を受け付けた時刻。待機していなければ nil。
    private var armedAt: TimeInterval?

    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    /// 2回目待ちの状態か。
    public var isArmed: Bool { armedAt != nil }

    /// ⌘Q 押下時の判定。
    /// - Parameter now: 単調増加する現在時刻（秒）。
    /// - Returns: イベントを握りつぶすか通すか。
    public mutating func handleQuitKey(now: TimeInterval) -> Decision {
        if let armedAt, now - armedAt <= interval {
            // 猶予時間内の2回目 → 通して終了させる。
            self.armedAt = nil
            return .passThrough
        }
        // 1回目、または猶予を過ぎていて改めて1回目とみなす場合。
        armedAt = now
        return .consumeAndArm
    }

    /// 待機状態を解除する（タイムアウトや無効化のとき）。
    public mutating func reset() {
        armedAt = nil
    }
}
