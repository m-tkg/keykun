import Foundation

/// 任意の物理修飾キー（`ModifierKey` = 種別 + 左右）の「単押し（長押しでない・他キー併用なし）」を
/// 検知する純粋ロジック。`ModifierTapDetector`（左右⌘専用）を `ModifierKey` キーへ一般化したもの。
///
/// ソロタップは同時に1キーしか成立しないため、候補は1つだけ保持する。
/// CGEventTap に依存しないため単体テスト可能。時刻は呼び出し側から `now`（単調増加秒）として注入する。
public struct ModifierKeyTapDetector {
    /// 単押しとみなす最大押下時間（秒）。これを超えると長押し扱いで発火しない。
    public var threshold: TimeInterval

    private struct Candidate {
        let key: ModifierKey
        let downTime: TimeInterval
        var isValid: Bool
    }

    private var candidate: Candidate?

    public init(threshold: TimeInterval = 0.3) {
        self.threshold = threshold
    }

    /// 修飾キーが押された。
    /// - Parameter otherModifiersHeld: 押下時点で他の修飾キーが押されているか（コンボ判定）。
    public mutating func keyDown(_ key: ModifierKey, otherModifiersHeld: Bool, now: TimeInterval) {
        candidate = Candidate(key: key, downTime: now, isValid: !otherModifiersHeld)
    }

    /// 修飾キーが離された。単押し成立なら該当キーを返す。
    public mutating func keyUp(_ key: ModifierKey, now: TimeInterval) -> ModifierKey? {
        guard let current = candidate, current.key == key else {
            // 候補と異なるキーの解放は無視（候補は保持したまま）。
            return nil
        }
        candidate = nil
        guard current.isValid, now - current.downTime <= threshold else { return nil }
        return key
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
