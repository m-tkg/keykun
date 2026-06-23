import AppKit
import OSLog
import KeykunCore

private let log = Logger(subsystem: "com.mtkg.keykun", category: "app")

/// アプリ本体。設定の読込・反映、ステータスバー UI と設定ウィンドウの配線、
/// アクセシビリティ権限の取得を担う。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore(url: SettingsStore.defaultURL())

    // 共有イベントタップと各機能ハンドラ。
    private let eventTap = KeyEventTap()
    private let safeQuit = SafeQuitHandler()
    private let inputSwitch = InputSwitchHandler()

    private var statusBar: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var permissionTimer: Timer?
    private var settings = Settings.default

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = store.load()
        applySettings(settings)

        eventTap.add(safeQuit)
        eventTap.add(inputSwitch)

        statusBar = StatusBarController(
            openSettings: { [weak self] in self?.openSettings() },
            checkPermission: { AccessibilityPermission.requestIfNeeded() },
            quit: { NSApp.terminate(nil) }
        )

        startTapWhenPermitted()
    }

    /// 設定を各ハンドラに反映する。
    private func applySettings(_ settings: Settings) {
        safeQuit.isEnabled = settings.safeQuit.isEnabled
        safeQuit.interval = settings.safeQuit.interval
        inputSwitch.update(settings.inputSwitch)
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                initialSettings: settings,
                onApply: { [weak self] newSettings in
                    guard let self else { return }
                    self.settings = newSettings
                    try? self.store.save(newSettings)
                    self.applySettings(newSettings)
                }
            )
        }
        settingsWindowController?.show()
    }

    // MARK: - アクセシビリティ権限と起動

    /// アクセシビリティ許可があればタップを開始する。
    /// 無ければプロンプトを出し、許可されるまで定期的に再試行する（再起動不要）。
    private func startTapWhenPermitted() {
        if eventTap.start() {
            log.info("event tap started")
            return
        }

        AccessibilityPermission.requestIfNeeded()
        showPermissionAlert()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.eventTap.start() {
                    log.info("event tap started after permission grant")
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.string("permission.alert.title")
        alert.informativeText = L.string("permission.alert.body")
        alert.addButton(withTitle: L.string("permission.button.open"))
        alert.addButton(withTitle: L.string("permission.button.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSettings()
        }
    }
}
