import AppKit
import OSLog

private let log = Logger(subsystem: "com.mtkg.keykun", category: "tap")

/// キーイベントを観測するハンドラ。複数機能で CGEventTap を共有するための共通インターフェース。
@MainActor
protocol KeyEventHandler: AnyObject {
    /// イベントを観測する。イベントを消費（握りつぶす）したい場合は true を返す。
    /// 状態更新のため、消費しない機能でも必ず観測する（戻り値 false）。
    func handle(type: CGEventType, event: CGEvent) -> Bool
}

/// CGEventTap を1つだけ生成し、登録された複数のハンドラへイベントを配信する。
/// 今後キー機能を増やすときは、`KeyEventHandler` を実装して `add(_:)` で登録する。
@MainActor
final class KeyEventTap {
    private var handlers: [KeyEventHandler] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func add(_ handler: KeyEventHandler) {
        handlers.append(handler)
    }

    /// イベントタップを生成して監視を開始する。
    /// アクセシビリティ許可が無いと生成に失敗するため、成否を返す。
    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        // keyDown（通常キー）と flagsChanged（修飾キーの押下/解放）を購読する。
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<KeyEventTap>.fromOpaque(refcon!).takeUnretainedValue()
            return MainActor.assumeIsolated { tap.route(type: type, event: event) }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("CGEvent.tapCreate failed (accessibility not granted?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        log.info("event tap started")
        return true
    }

    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // システムによってタップが無効化された場合は再有効化して素通しする。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // すべてのハンドラに観測させ、いずれかが消費を要求したら握りつぶす。
        var consume = false
        for handler in handlers {
            if handler.handle(type: type, event: event) {
                consume = true
            }
        }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
