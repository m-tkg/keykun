import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KeykunCore

/// 設定ダイアログの編集状態。編集は作業コピー上で行い、Apply/OK で確定する。
@MainActor
final class SettingsViewModel: ObservableObject {
    /// 編集中の作業コピー。
    @Published var settings: KeykunCore.Settings
    /// 直近に確定（Apply/OK）した内容。Cancel 時の復帰先。
    private var committed: KeykunCore.Settings
    private let onApply: (KeykunCore.Settings) -> Void

    init(settings: KeykunCore.Settings, onApply: @escaping (KeykunCore.Settings) -> Void) {
        self.settings = settings
        self.committed = settings
        self.onApply = onApply
    }

    /// 未確定の変更があるか。
    var hasChanges: Bool { settings != committed }

    /// 作業コピーを確定し保存・反映する。
    func apply() {
        committed = settings
        onApply(settings)
    }

    /// 未確定の変更を破棄して直近の確定内容に戻す。
    func revert() {
        settings = committed
    }
}

/// 設定ダイアログ本体。タブで機能ごとの設定を切り替える。
/// 今後キー機能を増やす場合は、TabView 内にタブを追加する。
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var loginItem: LoginItemController
    let onClose: () -> Void

    @State private var loginItemError: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsTab(loginItem: loginItem, errorMessage: $loginItemError)
                    .tabItem { Text(L.string("tab.general")) }

                SafeQuitSettingsTab(settings: $viewModel.settings.safeQuit)
                    .tabItem { Text(L.string("tab.safe_quit")) }

                InputSwitchSettingsTab(settings: $viewModel.settings.inputSwitch)
                    .tabItem { Text(L.string("tab.input_switch")) }

                ModifierLaunchSettingsTab(
                    settings: $viewModel.settings.modifierDoublePress,
                    hasConflict: viewModel.settings.hasModifierConflict
                )
                .tabItem { Text(L.string("tab.modifier_launch")) }
                // 将来のキー機能タブはここに追加する。
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button(L.string("button.cancel")) {
                    viewModel.revert()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button(L.string("button.apply")) {
                    viewModel.apply()
                }
                // 衝突状態（同じ⌘に入力切替と二度押し起動）のままでは保存させない。
                .disabled(!viewModel.hasChanges || viewModel.settings.hasModifierConflict)

                Button(L.string("button.ok")) {
                    viewModel.apply()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.settings.hasModifierConflict)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .alert(L.string("alert.error.title"), isPresented: Binding(
            get: { loginItemError != nil },
            set: { if !$0 { loginItemError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
    }
}

/// 「一般」タブ。ログイン時の自動起動とバージョン表示。
struct GeneralSettingsTab: View {
    @ObservedObject var loginItem: LoginItemController
    @SwiftUI.Binding var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ログイン項目はシステム側が source of truth。トグル操作で即時反映する。
            Toggle(L.string("settings.launch_at_login"), isOn: Binding(
                get: { loginItem.isEnabled },
                set: { newValue in
                    if let message = loginItem.setEnabled(newValue) {
                        errorMessage = message
                    }
                }
            ))

            Text(L.format("settings.version", UpdateService.currentVersion))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「安全な Quit」タブ。⌘Q 二度押しの有効/無効と猶予時間を設定する。
struct SafeQuitSettingsTab: View {
    @SwiftUI.Binding var settings: SafeQuitSettings

    /// 選べる猶予時間の候補（秒）。
    private let intervalOptions: [TimeInterval] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $settings.isEnabled) {
                Text(L.string("safe_quit.enabled"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("safe_quit.interval"))
                Spacer(minLength: 12)
                Picker("", selection: $settings.interval) {
                    ForEach(intervalOptions, id: \.self) { value in
                        Text(L.format("safe_quit.interval.seconds", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(!settings.isEnabled)
            }

            Text(L.string("safe_quit.description"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「入力切り替え」タブ。左右 Command の単押しに送出キー（英数/かな）を割り当てる。
struct InputSwitchSettingsTab: View {
    @SwiftUI.Binding var settings: InputSwitchSettings

    /// 単押しとみなす最大押下時間の候補（秒）。
    private let thresholdOptions: [TimeInterval] = [0.3, 0.5, 0.7, 1.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $settings.isEnabled) {
                Text(L.string("input_switch.enabled"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionPicker(title: L.string("input_switch.left"), selection: $settings.leftCommandAction)
            actionPicker(title: L.string("input_switch.right"), selection: $settings.rightCommandAction)

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("input_switch.threshold"))
                Spacer(minLength: 12)
                Picker("", selection: $settings.tapThreshold) {
                    ForEach(thresholdOptions, id: \.self) { value in
                        Text(L.format("common.seconds", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(!settings.isEnabled)
            }

            Text(L.string("input_switch.description"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 送出キー選択 Picker（なし / 英数 / かな）。
    private func actionPicker(title: String, selection: SwiftUI.Binding<InputSwitchAction>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                Text(L.string("input_switch.action.none")).tag(InputSwitchAction.none)
                Text(L.string("input_switch.action.eisu")).tag(InputSwitchAction.eisu)
                Text(L.string("input_switch.action.kana")).tag(InputSwitchAction.kana)
            }
            .labelsHidden()
            .frame(width: 200)
            .disabled(!settings.isEnabled)
        }
    }
}

/// 「二度押しでアプリ起動」タブ。(修飾キー, 左右) ごとに起動アプリを割り当てる行を、
/// ＋/－ で複数追加・削除できる。
struct ModifierLaunchSettingsTab: View {
    @SwiftUI.Binding var settings: ModifierDoublePressSettings
    /// 入力切替（⌘単押し）と⌘で競合しているか。
    let hasConflict: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $settings.isEnabled) {
                Text(L.string("modifier_launch.enabled"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 衝突時は警告し、保存は Apply/OK 側で無効化する。
            if hasConflict {
                Text(L.string("modifier_launch.conflict"))
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 割り当て行のリスト。
            VStack(alignment: .leading, spacing: 6) {
                ForEach($settings.bindings) { $binding in
                    bindingRow($binding)
                }
                Button(action: addBinding) {
                    Label(L.string("modifier_launch.add"), systemImage: "plus")
                }
                .disabled(!settings.isEnabled)
            }

            Text(L.string("modifier_launch.description"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 1 行ぶんの割り当て: 修飾キー種別 / 左右 / アプリ選択 / 削除（－）。
    private func bindingRow(_ binding: SwiftUI.Binding<ModifierLaunchBinding>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: binding.modifier) {
                Text(L.string("modifier_launch.modifier.command")).tag(TargetModifier.command)
                Text(L.string("modifier_launch.modifier.option")).tag(TargetModifier.option)
                Text(L.string("modifier_launch.modifier.control")).tag(TargetModifier.control)
                Text(L.string("modifier_launch.modifier.shift")).tag(TargetModifier.shift)
            }
            .labelsHidden()
            .frame(width: 120)

            Picker("", selection: binding.side) {
                Text(L.string("modifier_launch.side.left")).tag(LaunchSide.left)
                Text(L.string("modifier_launch.side.right")).tag(LaunchSide.right)
                Text(L.string("modifier_launch.side.both")).tag(LaunchSide.both)
            }
            .labelsHidden()
            .frame(width: 100)

            Button {
                chooseApp(into: binding.app)
            } label: {
                Text(binding.wrappedValue.app.isAssigned
                     ? binding.wrappedValue.app.displayName
                     : L.string("modifier_launch.choose_app"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            Button {
                removeBinding(id: binding.wrappedValue.id)
            } label: {
                Image(systemName: "minus")
            }
        }
        .disabled(!settings.isEnabled)
    }

    private func addBinding() {
        settings.bindings.append(ModifierLaunchBinding())
    }

    private func removeBinding(id: UUID) {
        settings.bindings.removeAll { $0.id == id }
    }

    /// /Applications を起点に .app を選ばせ、bundle identifier と表示名を取り込む。
    private func chooseApp(into app: SwiftUI.Binding<AppTarget>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
        else { return }
        let name = FileManager.default.displayName(atPath: url.path)
        app.wrappedValue = AppTarget(bundleIdentifier: bundleID, displayName: name)
    }
}
