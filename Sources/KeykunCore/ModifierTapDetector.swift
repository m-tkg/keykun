import Foundation

/// 修飾キーの左右。
public enum ModifierSide: String, Codable, Equatable, CaseIterable {
    case left
    case right
}

/// 左右 Command の「単押し（長押しでない・他キー併用なし）」を検知する純粋ロジック。
///
/// CGEventTap に依存しないため単体テスト可能。時刻は呼び出し側から `now`（単調増加秒）として注入する。
///
/// 判定:
///   - ⌘押下〜解放の間に他キー（通常キーや他の修飾キー）が無い
///   - 押下時点で他の修飾キー（反対側⌘含む）が押されていない
///   - 押下から解放までが `threshold` 以内（長押しでない）
/// を満たしたときだけ、解放時に該当サイドを返す。
public struct ModifierTapDetector {
    /// 単押しとみなす最大押下時間（秒）。これを超えると長押し扱いで発火しない。
    public var threshold: TimeInterval

    private struct Candidate {
        let side: ModifierSide
        let downTime: TimeInterval
        var isValid: Bool
    }

    private var candidate: Candidate?

    public init(threshold: TimeInterval = 0.3) {
        self.threshold = threshold
    }

    /// Command が押された。
    /// - Parameter otherModifiersHeld: 押下時点で他の修飾キー（反対側⌘ / shift / control / option）が押されているか。
    public mutating func commandDown(side: ModifierSide, otherModifiersHeld: Bool, now: TimeInterval) {
        // 新しい候補を開始。他修飾が既に押されていれば最初から無効（コンボ）。
        candidate = Candidate(side: side, downTime: now, isValid: !otherModifiersHeld)
    }

    /// Command が離された。単押し成立なら該当サイドを返す。
    public mutating func commandUp(side: ModifierSide, now: TimeInterval) -> ModifierSide? {
        guard let current = candidate, current.side == side else {
            // 候補と異なるサイドの解放は無視（候補は保持したまま）。
            return nil
        }
        candidate = nil
        guard current.isValid, now - current.downTime <= threshold else { return nil }
        return side
    }

    /// 押下中に通常キーや他修飾が押された → 候補をコンボ扱いで無効化する。
    public mutating func contaminate() {
        candidate?.isValid = false
    }

    /// 候補をクリアする（イベント取りこぼし後の状態固着を防ぐため）。
    public mutating func reset() {
        candidate = nil
    }
}
