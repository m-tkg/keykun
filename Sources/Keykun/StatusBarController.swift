import AppKit

/// メニューバー常駐アイコンとメニューを管理する。
/// 設定項目自体は設定ダイアログに集約し、メニューは入口だけを提供する。
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    /// ステータスメニュー本体。kuntraykun 連携時はこのメニューを指定座標へ popUp する。
    private let menu = NSMenu()

    private let openSettings: () -> Void
    private let checkPermission: () -> Void
    private let checkForUpdate: () -> Void
    private let quitApp: () -> Void
    private var updateItem: NSMenuItem!

    /// アップデート有無を示すアイコン右下の赤バッジ（小さな赤丸）。
    /// ベース画像は template のまま自動着色させ、色付きのバッジだけ別 view で重ねる。
    private var badgeView: NSView?
    private let badgeSize: CGFloat = 7

    private static var checkUpdateTitle: String { L.string("menu.check_update") }

    /// ローカル検証ビルド（バンドルID が `.local` で終わる）かどうか。
    private var isLocalBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".local")
    }

    init(
        openSettings: @escaping () -> Void,
        checkPermission: @escaping () -> Void,
        checkForUpdate: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.openSettings = openSettings
        self.checkPermission = checkPermission
        self.checkForUpdate = checkForUpdate
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
            // ローカルビルドは「ローカル」を併記して本番と区別する。
            if isLocalBuild {
                button.title = " " + L.string("menu_bar.local")
                button.imagePosition = .imageLeading
            }
            // アイコングリフの右下に赤バッジを重ねる（既定は非表示）。
            let iconWidth = button.image?.size.width ?? badgeSize * 2
            installBadge(on: button, iconWidth: iconWidth)
        }
        // kuntraykun 一覧用に、現在のメニューバーアイコンを共有場所へ書き出す（連携 v2）。
        KuntraykunIconExport.export(statusItem.button?.image)

        // 先頭にバージョン情報（操作不可）。ローカルビルドは併記する。
        var versionTitle = L.format("menu.version", UpdateService.currentVersion)
        if isLocalBuild { versionTitle += " (" + L.string("menu_bar.local") + ")" }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.settings"), action: #selector(handleOpenSettings), key: ","))
        menu.addItem(menuItem(title: L.string("menu.check_permission"), action: #selector(handleCheckPermission), key: ""))
        updateItem = menuItem(title: Self.checkUpdateTitle, action: #selector(handleCheckForUpdate), key: "")
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.quit"), action: #selector(handleQuit), key: "q"))
        statusItem.menu = menu
    }

    /// 新バージョンが利用可能なときにメニュー文言を変更し、赤バッジを表示する。
    func setUpdateAvailable(tag: String) {
        updateItem.title = L.format("menu.install_update", tag)
        badgeView?.isHidden = false
        // メニュー文言が変わったので kuntraykun 用スナップショットを書き出し直す（連携 v4）。
        exportMenuSnapshot()
    }

    /// 最新（更新なし）状態に戻し、赤バッジを消す。
    func clearUpdateAvailable() {
        updateItem.title = Self.checkUpdateTitle
        badgeView?.isHidden = true
        exportMenuSnapshot()
    }

    // MARK: - kuntraykun 連携

    /// kuntraykun に集約されている間、自分のメニューバーアイコンを隠す/戻す。
    func setManagedHidden(_ hidden: Bool) {
        statusItem.isVisible = !hidden
    }

    /// 自分のステータスメニューを指定スクリーン座標（左下原点）に表示する。
    func popUpMenu(at point: NSPoint) {
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// メニュー構造を kuntraykun 用の共有場所へ書き出す（連携 v4）。
    /// 起動時・requestMenu 受信時・メニュー内容が変わる箇所から呼ぶ。
    func exportMenuSnapshot() {
        KuntraykunMenuExport.export(menu)
    }

    /// kuntraykun のサブメニューでクリックされた項目（インデックスパス ID）を実行する（連携 v4）。
    func performMenuItem(id: String) -> Bool {
        KuntraykunMenuExport.performItem(id: id, in: menu)
    }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// アイコングリフの右下に赤バッジ（小さな赤丸）を重ねる。
    /// ベース画像は template のまま自動着色を維持し、色付きのバッジだけ別レイヤーで描く。
    /// 位置は Auto Layout で固定するため bounds 確定タイミングに依存しない。
    /// trailing ではなくアイコン幅基準で固定し、ローカルビルドの " Local" 併記時も
    /// 常にアイコングリフの右下に乗るようにする。
    private func installBadge(on button: NSStatusBarButton, iconWidth: CGFloat) {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = badgeSize / 2
        // メニューバー背景に溶けないよう細い縁取りを付ける。
        badge.layer?.borderWidth = 0.5
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            badge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: iconWidth - badgeSize + 1),
            badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
        ])
        badgeView = badge
    }

    @objc private func handleOpenSettings() { openSettings() }
    @objc private func handleCheckPermission() { checkPermission() }
    @objc private func handleCheckForUpdate() { checkForUpdate() }
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
