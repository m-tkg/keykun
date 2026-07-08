import AppKit
import KunAppKit

// メニューバー常駐アプリとして起動する（Dock アイコンなし）。
// トップレベルはメインスレッドで実行されるため、MainActor として扱う。
MainActor.assumeIsolated {
    // 多重起動防止: 同じ bundle ID の他インスタンスが既に動いていたら、そちらを前面に出して起動しない
    // （イベントタップが二重に走るのを防ぐ）。
    KunAppLaunch.terminateIfAlreadyRunning()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
