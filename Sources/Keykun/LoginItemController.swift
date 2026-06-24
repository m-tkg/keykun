import ServiceManagement

/// ログイン時の自動起動を司る薄いラッパ。
/// macOS 13+ の `SMAppService.mainApp` を source of truth とし、状態は
/// システム側が永続化する（`Settings`/JSON には保存しない）。
@MainActor
final class LoginItemController: ObservableObject {
    private let service = SMAppService.mainApp

    /// 現在ログイン項目として有効か。トグル表示用。
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// システムの現在状態を再読込する（外部で変更された場合に同期する）。
    func refresh() {
        isEnabled = service.status == .enabled
    }

    /// 自動起動の有効/無効を切り替える。失敗時はエラーメッセージを返す。
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            refresh()
            return error.localizedDescription
        }
        refresh()
        // ユーザーがシステム設定で「ログイン項目」を無効にしていると、
        // register しても .requiresApproval になり有効化されない。
        if enabled && service.status == .requiresApproval {
            return L.string("login_item.requires_approval")
        }
        return nil
    }
}
