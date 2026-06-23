import AppKit

/// 画面中央に「もう一度 ⌘Q で終了」を表示する軽量な HUD。
///
/// フロントアプリのキー入力フォーカスを奪わないよう、
/// アクティブにならないボーダーレスウィンドウを使う。
@MainActor
final class HUDController {
    private var window: NSWindow?

    func show(message: String) {
        hide()

        let size = NSSize(width: 280, height: 72)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // 角丸の半透明背景。
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (size.height - 22) / 2, width: size.width, height: 22)
        background.addSubview(label)

        window.contentView = background
        centerOnActiveScreen(window, size: size)
        window.orderFrontRegardless()

        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func centerOnActiveScreen(_ window: NSWindow, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
