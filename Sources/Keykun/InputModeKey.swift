import CoreGraphics
import OSLog

private let log = Logger(subsystem: "com.mtkg.keykun", category: "inputmode")

/// 「英数」「かな」キーの信号を送出して IME のモードを切り替える（Karabiner と同じ方式）。
///
/// 入力ソース選択（TISSelectInputSource）は「すでに選択中のソースを選ぶと no-op」になり、
/// azooKey のような複数モードを持つ IME では確実に切り替わらない。英数/かなキーは IME への
/// モード切替コマンドなので、現在の選択状態に関係なく確実にモードが切り替わる。
enum InputModeKey {
    /// 「英数」キーの仮想キーコード（kVK_JIS_Eisu）。
    static let eisu: CGKeyCode = 0x66  // 102
    /// 「かな」キーの仮想キーコード（kVK_JIS_Kana）。
    static let kana: CGKeyCode = 0x68  // 104

    /// 指定キーの down/up を送出する。
    /// IME はハードウェア相当のイベントを見るため、HID レベル（`.cghidEventTap`）に post する。
    static func post(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("failed to create key events for keyCode=\(keyCode)")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
