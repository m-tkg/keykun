import AppKit
import KeykunCore

/// 「安全な Quit」: ⌘Q の二度押し判定を行うイベントハンドラ。
/// 1回目は握りつぶし HUD を表示、猶予時間内の2回目は通してアプリを終了させる。
@MainActor
final class SafeQuitHandler: KeyEventHandler {
    /// 機能の有効/無効。無効時は素通しする。
    var isEnabled = true {
        didSet { if !isEnabled { disarm() } }
    }

    /// 2回目を受け付ける猶予時間（秒）。
    var interval: TimeInterval {
        get { decider.interval }
        set { decider.interval = newValue }
    }

    private var decider = DoublePressDecider(interval: 1.0)
    private let hud = HUDController()
    private var resetTimer: Timer?

    /// macOS の Q キーの仮想キーコード（kVK_ANSI_Q）。
    private let keyCodeQ: Int64 = 12

    /// 単調増加する現在時刻（秒）。
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard isEnabled, type == .keyDown, isCommandQ(event) else { return false }

        switch decider.handleQuitKey(now: now) {
        case .passThrough:
            // 2回目: そのまま通してアプリを終了させる。
            hideHUD()
            return false
        case .consumeAndArm:
            // 1回目: 握りつぶして待機状態に入る。
            arm()
            return true
        }
    }

    /// 「command のみ」かつ Q かどうかを判定する（caps lock は無視）。
    private func isCommandQ(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCodeQ else { return false }
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        return event.flags.intersection(relevant) == .maskCommand
    }

    private func arm() {
        hud.show(message: L.string("hud.press_again"))
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.disarm() }
        }
    }

    private func disarm() {
        decider.reset()
        hideHUD()
    }

    private func hideHUD() {
        resetTimer?.invalidate()
        resetTimer = nil
        hud.hide()
    }
}
