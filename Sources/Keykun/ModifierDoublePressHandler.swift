import AppKit
import KeykunCore
import os

/// 「修飾キー二度押しでアプリ起動」: 割り当てた物理修飾キー（種別 ⌘/⌥/⌃/⇧ × 左右）の
/// いずれかを単押し2回続けると、対応するアプリを起動するイベントハンドラ。
///
/// 判定は純粋ロジックに委ねる:
///   - `ModifierKeyTapDetector` … 単押し（長押しでない・他キー併用なし）の検知
///   - `ModifierKeyDoublePressDecider` … 同じキーの猶予時間内2回目の検知
/// 本クラスは flagsChanged の解釈（どのキーが down/up したか）を `ModifierFlagsInterpreter` に委ね、
/// keyDown / 他修飾の同時押しでコンボ（汚染）を通知する。
/// イベントは消費しない（通常の修飾キー操作と両立）。
@MainActor
final class ModifierDoublePressHandler: KeyEventHandler {
    private var settings = ModifierDoublePressSettings()
    private var detector = ModifierKeyTapDetector(threshold: ModifierDoublePressTiming.tapThreshold)
    private var decider = ModifierKeyDoublePressDecider(interval: ModifierDoublePressTiming.interval)

    /// flagsChanged の解釈器。監視対象に関係なく全修飾キーを追跡する
    /// （同種別の反対側の押下状態が汚染判定に必要なため）。監視フィルタは本クラスで行う。
    private var interpreter = ModifierFlagsInterpreter()

    /// 監視対象（アプリ割り当て済み）の物理キー。重複は除く。
    private var watchedKeys: Set<ModifierKey> = []

    private let log = Logger(subsystem: "com.mtkg.keykun", category: "ModifierDoublePress")

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 設定を反映する。
    func update(_ settings: ModifierDoublePressSettings) {
        self.settings = settings
        // アプリ割り当て済みのキーだけを監視（`.both` の左右展開・重複除去はコア側で実施）。
        watchedKeys = Set(settings.watchedKeys)
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

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let result = interpreter.interpret(keyCode: keyCode, rawFlags: event.flags.rawValue)

        switch result.transition {
        case .down(let key) where watchedKeys.contains(key):
            detector.keyDown(key, otherModifiersHeld: result.otherModifiersHeld, now: now)
        case .up(let key) where watchedKeys.contains(key):
            if let fired = detector.keyUp(key, now: now) {
                handleTap(fired)
            }
        default:
            break
        }

        // 対象キー保持中に他の修飾キーが加わったらコンボ扱い。
        if result.multipleModifiersHeld {
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
        guard let app, app.isAssigned else { return }
        let bundleID = app.bundleIdentifier
        // イベントタップのコールバック内で再入的に重い処理を行わないよう、復帰後に実行する。
        DispatchQueue.main.async { [log] in
            // 既に最前面のアプリなら隠す（押すたびに前面化↔退避するトグル）。
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.bundleIdentifier == bundleID {
                frontmost.hide()
                return
            }
            // それ以外は起動／前面化する。
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    log.error("Failed to launch \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// イベント取りこぼし（タップ無効化）後に状態が固着しないよう、観測状態をリセットする。
    func reset() {
        interpreter.reset()
        detector.reset()
        decider.reset()
    }
}
