import AppKit
import OSLog
import KeykunCore
import KunIntegrationBridge
import KunUpdateKit

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
    private let modifierDoublePress = ModifierDoublePressHandler()

    private var statusBar: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var permissionTimer: Timer?
    private var kuntraykunBridge: KuntraykunBridge?
    private var settings = Settings.default

    // アップデート関連。
    private let updateService = UpdateService()
    private lazy var selfUpdater = SelfUpdater(service: updateService)
    private var availableRelease: ReleaseInfo?
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = store.load()
        applySettings(settings)

        eventTap.add(safeQuit)
        eventTap.add(inputSwitch)
        eventTap.add(modifierDoublePress)

        statusBar = StatusBarController(
            openSettings: { [weak self] in self?.openSettings() },
            checkPermission: { AccessibilityPermission.requestIfNeeded() },
            checkForUpdate: { [weak self] in self?.startUpdateCheck(interactive: true) },
            quit: { NSApp.terminate(nil) }
        )

        startTapWhenPermitted()

        // kuntraykun 連携（kunkit）: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        // v4: メニュー構造を共有してサブメニュー表示・項目実行にも応じる（初回書き出しは start() 内）。
        let bridge = statusBar!.makeKuntraykunBridge()
        bridge.start()
        kuntraykunBridge = bridge
        // メニュー文言の変化（アップデート有無）でスナップショットを書き出し直す。
        statusBar?.onMenuContentChanged = { [weak self] in
            self?.kuntraykunBridge?.exportMenuSnapshot()
        }

        // 起動時にサイレントで更新チェック（あればメニュー文言を変更＋赤バッジ表示）。
        startUpdateCheck(interactive: false)
        // 以降は定期的に監視し、スリープ復帰時にも即チェックする。
        scheduleUpdateChecks()
    }

    /// 設定を各ハンドラに反映する。
    private func applySettings(_ settings: Settings) {
        safeQuit.isEnabled = settings.safeQuit.isEnabled
        safeQuit.interval = settings.safeQuit.interval
        inputSwitch.update(settings.inputSwitch)
        modifierDoublePress.update(settings.modifierDoublePress)
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

    // MARK: - アップデート

    /// アップデートを定期的に監視する。Timer はスリープ中は発火しないため、
    /// `NSWorkspace.didWakeNotification` を購読してスリープ復帰時にも即チェックする。
    private func scheduleUpdateChecks() {
        let timer = Timer.scheduledTimer(
            withTimeInterval: KunUpdateSchedule.checkInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startUpdateCheck(interactive: false) }
        }
        timer.tolerance = KunUpdateSchedule.checkIntervalTolerance  // 省電力のためコアレッシングを許可。
        updateTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startUpdateCheck(interactive: false) }
        }
    }

    /// 最新リリースを取得してバージョン比較する。
    /// interactive=false: 起動時のサイレントチェック（結果はメニュー文言に反映するのみ）。
    /// interactive=true : メニューからの手動チェック（結果をダイアログで提示）。
    private func startUpdateCheck(interactive: Bool) {
        Task { @MainActor in
            do {
                let release = try await updateService.fetchLatestRelease()
                let isNewer = VersionComparator.isNewer(
                    tag: release.tagName, than: UpdateService.currentVersion)
                if isNewer {
                    availableRelease = release
                    statusBar?.setUpdateAvailable(tag: release.tagName)
                } else {
                    availableRelease = nil
                    statusBar?.clearUpdateAvailable()
                }
                // kuntraykun にもアップデート有無を伝える（集約バッジ/赤丸用）。
                kuntraykunBridge?.reportUpdate(isNewer)
                if interactive {
                    if isNewer {
                        promptInstall(release)
                    } else {
                        showInfo(L.format("update.latest", UpdateService.currentVersion))
                    }
                }
            } catch {
                log.error("update check failed: \(error.localizedDescription, privacy: .public)")
                if interactive {
                    showError(L.format("update.check_failed", error.localizedDescription))
                }
            }
        }
    }

    private func promptInstall(_ release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.format("update.available.title", release.tagName)
        alert.informativeText = L.format("update.available.body", UpdateService.currentVersion)
        alert.addButton(withTitle: L.string("update.button.update"))
        alert.addButton(withTitle: L.string("update.button.open_release"))
        alert.addButton(withTitle: L.string("button.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func performUpdate(_ release: ReleaseInfo) {
        Task { @MainActor in
            do {
                try await selfUpdater.performUpdate(to: release)
                // 成功時はアプリが終了するためここには戻らない。
            } catch {
                log.error("self-update failed: \(error.localizedDescription, privacy: .public)")
                showError(L.format("update.failed", error.localizedDescription))
            }
        }
    }

    private func showInfo(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Keykun"
        alert.informativeText = text
        alert.runModal()
    }

    private func showError(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.string("alert.error.title")
        alert.informativeText = text
        alert.runModal()
    }
}
