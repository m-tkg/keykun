import AppKit
import KeykunCore
import os

/// 「修飾キー二度押しでアプリ起動」: 割り当てた物理修飾キー（種別 ⌘/⌥/⌃/⇧ × 左右）の
/// いずれかを単押し2回続けると、対応するアプリを起動するイベントハンドラ。
///
/// 判定は純粋ロジックに委ねる:
///   - `ModifierKeyTapDetector` … 単押し（長押しでない・他キー併用なし）の検知
///   - `ModifierKeyDoublePressDecider` … 同じキーの猶予時間内2回目の検知
/// 本クラスは flagsChanged から、割り当て済みの各物理キーの押下/解放を device 依存ビットで判定し、
/// keyDown / 他修飾の同時押しでコンボ（汚染）を通知する。
/// イベントは消費しない（通常の修飾キー操作と両立）。
@MainActor
final class ModifierDoublePressHandler: KeyEventHandler {
    private var settings = ModifierDoublePressSettings()
    private var detector = ModifierKeyTapDetector(threshold: ModifierDoublePressTiming.tapThreshold)
    private var decider = ModifierKeyDoublePressDecider(interval: ModifierDoublePressTiming.interval)

    /// 監視対象（アプリ割り当て済み）の物理キー。重複は除く。
    private var watchedKeys: [ModifierKey] = []
    /// 各監視キーの直近の押下状態。
    private var down: [ModifierKey: Bool] = [:]

    /// 全修飾キーの device 依存ビット（押下中の修飾キー数を数えてコンボ判定に使う）。
    private let allModifierBits: [UInt64] =
        TargetModifier.allCases.flatMap { [$0.leftBit, $0.rightBit] }

    private let log = Logger(subsystem: "com.mtkg.keykun", category: "ModifierDoublePress")

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 設定を反映する。
    func update(_ settings: ModifierDoublePressSettings) {
        self.settings = settings
        // アプリ割り当て済みのキーだけを監視（重複除去）。
        var seen = Set<ModifierKey>()
        watchedKeys = settings.bindings
            .filter { $0.app.isAssigned }
            .map { $0.key }
            .filter { seen.insert($0).inserted }
        // 監視対象が変わると押下状態の意味が変わるため、観測状態をリセットする。
        reset()
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard settings.isEnabled, !watchedKeys.isEmpty else { return false }

        if type == .keyDown {
            // 修飾キー保持中に通常キー → コンボ扱い（通常操作で誤発火しないように）。
            detector.contaminate()
            return false
        }

        guard type == .flagsChanged else { return false }

        let raw = event.flags.rawValue
        // 現在押されている修飾キーの数（複数なら単押しではない）。
        let pressedCount = allModifierBits.filter { raw & $0 != 0 }.count

        for key in watchedKeys {
            let newDown = (raw & key.deviceBit) != 0
            let wasDown = down[key] ?? false
            guard newDown != wasDown else { continue }
            if newDown {
                detector.keyDown(key, otherModifiersHeld: pressedCount > 1, now: now)
            } else if let fired = detector.keyUp(key, now: now) {
                handleTap(fired)
            }
            down[key] = newDown
        }

        // 対象キー保持中に他の修飾キーが加わったらコンボ扱い。
        if pressedCount > 1 {
            detector.contaminate()
        }

        return false
    }

    /// 単押しが成立したキーを二度押し判定器へ渡し、発火すればアプリを起動する。
    private func handleTap(_ key: ModifierKey) {
        if case .fired(let firedKey) = decider.tap(key: key, now: now) {
            launch(settings.app(for: firedKey))
        }
    }

    private func launch(_ app: AppTarget?) {
        guard let app, app.isAssigned,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        else { return }
        // イベントタップのコールバック内で再入的に重い処理を行わないよう、復帰後に起動する。
        DispatchQueue.main.async { [log] in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    log.error("Failed to launch \(app.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// イベント取りこぼし（タップ無効化）後に状態が固着しないよう、観測状態をリセットする。
    func reset() {
        down.removeAll()
        detector.reset()
        decider.reset()
    }
}
