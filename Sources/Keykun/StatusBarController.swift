import AppKit

/// メニューバー常駐アイコンとメニューを管理する。
/// 設定項目自体は設定ダイアログに集約し、メニューは入口だけを提供する。
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    private let openSettings: () -> Void
    private let checkPermission: () -> Void
    private let quitApp: () -> Void

    init(
        openSettings: @escaping () -> Void,
        checkPermission: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.openSettings = openSettings
        self.checkPermission = checkPermission
        self.quitApp = quit
        super.init()

        if let button = statusItem.button {
            if let template = Self.menuBarImage() {
                button.image = template
            } else if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: "Keykun") {
                button.image = symbol
            } else {
                button.title = "⌘"
            }
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: L.string("menu.settings"), action: #selector(handleOpenSettings), key: ","))
        menu.addItem(menuItem(title: L.string("menu.check_permission"), action: #selector(handleCheckPermission), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.quit"), action: #selector(handleQuit), key: "q"))
        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func handleOpenSettings() { openSettings() }
    @objc private func handleCheckPermission() { checkPermission() }
    @objc private func handleQuit() { quitApp() }

    /// メニューバー用のテンプレート（モノクロ）画像を返す。
    /// `Resources/MenuBarIcon.png`（黒インク＋アルファで形を持つ）を読み込み、
    /// テンプレート指定することでメニューバーの明暗に応じて黒/白に着色させる。
    /// 見つからなければ nil（呼び出し側が SF Symbol にフォールバック）。
    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        // メニューバーの高さに合わせる（18pt）。テンプレート指定で自動着色。
        let height: CGFloat = 18
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }
}
