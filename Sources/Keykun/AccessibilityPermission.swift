import AppKit
import ApplicationServices

/// アクセシビリティ権限の確認・要求。
/// CGEventTap によるキー入力監視に必要。
enum AccessibilityPermission {
    /// 既に許可されているか。
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 未許可ならシステムのダイアログを表示して要求する。許可済みなら true。
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定のアクセシビリティ画面を開く。
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
