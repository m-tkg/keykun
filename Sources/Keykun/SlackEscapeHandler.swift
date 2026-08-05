import AppKit
import CoreGraphics
import KeykunCore
import OSLog

private let slackEscapeLog = Logger(subsystem: "com.mtkg.keykun", category: "SlackEscape")

/// Slack が最前面のとき、Esc を Slack へ渡さず Ctrl-G として送出する。
///
/// グローバルな CGEventTap では「IME だけに Esc を届けてアプリには届けない」という分離はできないため、
/// SKK がキャンセル操作として扱う Ctrl-G に置き換える。Slack 側の Esc ショートカットを避けるのが目的。
@MainActor
final class SlackEscapeHandler: KeyEventHandler {
    private var settings = SlackEscapeSettings()
    private var consumeNextEscapeUp = false

    /// macOS の Esc キーの仮想キーコード（kVK_Escape）。
    private let keyCodeEscape: Int64 = 53

    /// Slack.app の bundle identifier。通常版に加えて beta/dev 系も許容する。
    private let slackBundleIdentifiers: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.tinyspeck.slackmacgap.beta",
        "com.tinyspeck.slackmacgap.dev",
    ]

    func update(_ settings: SlackEscapeSettings) {
        self.settings = settings
        if !settings.isEnabled {
            consumeNextEscapeUp = false
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard settings.isEnabled else { return false }
        guard isPlainEscape(event) else { return false }

        switch type {
        case .keyDown:
            guard isSlackFrontmost else { return false }
            consumeNextEscapeUp = true
            DispatchQueue.main.async {
                Self.postControlG()
            }
            return true

        case .keyUp:
            guard consumeNextEscapeUp else { return false }
            consumeNextEscapeUp = false
            return true

        default:
            return false
        }
    }

    func reset() {
        consumeNextEscapeUp = false
    }

    private var isSlackFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return slackBundleIdentifiers.contains(bundleID)
    }

    /// 修飾キーなしの Esc だけを対象にする。
    private func isPlainEscape(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCodeEscape else {
            return false
        }
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        return event.flags.intersection(relevant).isEmpty
    }

    /// SKK のキャンセル操作として一般的な Ctrl-G を送出する。
    private nonisolated static func postControlG() {
        let keyCodeG: CGKeyCode = 5
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeG, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeG, keyDown: false)
        else {
            slackEscapeLog.error("failed to create Ctrl-G events")
            return
        }

        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
