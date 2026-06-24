# CLAUDE.md

このファイルは、このリポジトリで作業する際のガイダンスを提供します。
メニューバー常駐アプリ共通の方針は上位ディレクトリの `../CLAUDE_base.md` を参照（本ファイルはその具体例）。

## ブランチ運用（必須）

- **`main` ブランチへ直接コミット/push しない**。変更は必ず **Pull Request 経由**で行う。
- 作業ブランチは**必ずその時点の最新の `main` から切る**（`git fetch origin && git switch main &&
  git pull --ff-only` で最新化してから分岐）。PR は `gh pr create` で作成し、マージはレビュー後。
- リリース用 Actions は `push: branches: [main]` で発火し main への push がそのままリリースに直結するため、
  事故防止のためにも main 直 push を避ける。

## プロジェクト概要

Keykun は macOS 用のキー操作カスタマイズツール（メニューバー常駐アプリ）。
第一の機能は「安全な Quit」＝ `⌘Q` を2回押さないとアプリを終了させない（Karabiner の
「command-q を2回押して終了」設定と同等の挙動を Karabiner なしで実現）。
外部依存なし（AppKit / ApplicationServices / SwiftUI のみ）の Swift Package Manager プロジェクト。
今後さまざまなキー設定機能を追加していく前提で、設定 UI はタブで拡張する構成にしている。

## コマンド

```sh
swift build                  # ビルド
swift test                   # 全テスト
swift test --filter <Name>   # 個別テスト（例: DoublePressDeciderTests）
swift run                    # 直接実行（開発時）
bash Scripts/bundle.sh       # .app バンドル生成（既定 release + Developer ID 署名）
AD_HOC=1 bash Scripts/bundle.sh   # 証明書が無い環境向けにアドホック署名
```

## アーキテクチャ

2 ターゲット構成。**純粋ロジックとプラットフォーム依存を分離**しているのが要点。

- **`KeykunCore`（ライブラリ / テスト対象）**: AppKit/CGEventTap に依存しないロジックとモデル。
  - `DoublePressDecider` — ⌘Q 二度押し判定の状態機械。時刻を `now`（単調増加秒）として注入する純粋ロジック。
    1回目は `.consumeAndArm`（握りつぶし）、猶予時間内の2回目は `.passThrough`（通す）を返す。
  - `ModifierTapDetector` — 左右 Command の「単押し（長押しでない・他キー併用なし）」検知の純粋ロジック。
    `commandDown`/`commandUp`/`contaminate` を時刻注入で受け、単押し成立時に `ModifierSide` を返す。
  - `Settings` / `SafeQuitSettings` / `InputSwitchSettings` — 設定モデル。機能ごとにサブ構造体を持ち、
    機能追加で拡張する。Codable は欠損キーを既定値で補完する（前方/後方互換）。
  - `SettingsStore` — 設定の JSON 永続化（`~/Library/Application Support/Keykun/settings.json`）。
    読込失敗時は `Settings.default` にフォールバックする。
- **`Keykun`（実行ファイル）**: CGEventTap / AppKit / SwiftUI 連携と UI。
  - `main.swift` — `NSApplication` 起動（`.accessory`、`MainActor.assumeIsolated`）
  - `AppDelegate` — 設定読込・各部品の配線・権限取得（`@MainActor`）
  - `KeyEventTap` — CGEventTap を1つだけ生成し、`keyDown` と `flagsChanged` を購読して
    登録された複数の `KeyEventHandler` へ配信する。いずれかが消費要求したらイベントを握りつぶす。
  - `SafeQuitHandler`（`KeyEventHandler`）— ⌘Q を抽出して `DoublePressDecider` に委譲。
    1回目は握りつぶし HUD 表示、2回目は通してアプリを終了させる。
  - `InputSwitchHandler`（`KeyEventHandler`）— `flagsChanged` から左右⌘の押下/解放を device 依存ビットで判定し、
    `ModifierTapDetector` に委譲。単押し成立時に `InputModeKey.post` で英数/かなキーを送出する（イベントは消費しない）。
  - `InputModeKey` — 英数(102)/かな(104)キーの CGEvent を `.cghidEventTap`（HID 相当）に post して IME のモードを切り替える。
  - `AccessibilityPermission` — アクセシビリティ権限の確認・要求・設定画面オープン
  - `LoginItemController` — ログイン時自動起動（`SMAppService.mainApp`）。状態はシステム側が source of truth
    で、`Settings`/JSON には保存しない。設定ダイアログの「一般」タブのトグルで即時反映する。
  - `StatusBarController` — メニューバー常駐メニュー（入口のみ。設定項目は設定ダイアログに集約）
  - `SettingsWindowController` / `SettingsView` — SwiftUI の設定ダイアログ。タブで機能ごとに分割
  - `HUDController` — 「もう一度 ⌘Q で終了」HUD
  - `Localization`（`L`）/ `Resources/{en,ja}.lproj/Localizable.strings` — GUI 文字列の多言語対応（後述）

データの流れ:
キー入力 → `KeyEventTap`（CGEventTap）が各ハンドラへ配信 →
`SafeQuitHandler` は ⌘Q を `DoublePressDecider` に渡し `.consumeAndArm` なら消費・`.passThrough` なら通す /
`InputSwitchHandler` は左右⌘の単押しを `ModifierTapDetector` で判定し成立時に英数/かなキーを送出する。

## 設計上の重要な前提（変更時に注意）

- **二度押し判定はコア層（`DoublePressDecider`）に閉じ込め、CGEventTap 非依存に保つ**。
  時刻は呼び出し側から注入し、テスト可能にする。アプリ側（`QuitGuard`）は単調増加時計
  （`ProcessInfo.processInfo.systemUptime`）を渡す。
- **⌘Q の判定条件**: 修飾キーは `command` のみを対象（`shift`/`control`/`option` が同時に押されていたら対象外）、
  `caps lock` は無視する（Karabiner 設定と同条件）。キーコードは `kVK_ANSI_Q`（12）。
- **CGEventTap にはアクセシビリティ権限が必須**。未許可だと `tapCreate` が nil を返すため、
  `AppDelegate` はプロンプトを出して許可されるまで再試行する（再起動不要）。
- **イベントタップは1つを共有**する（`KeyEventTap`）。機能ごとに別タップを作らず `KeyEventHandler` を登録する。
  全ハンドラがイベントを観測（状態更新のため）し、消費は OR で決まる。現状は「`SafeQuitHandler` のみ消費・
  `InputSwitchHandler` は消費しない」と責務が明確。複数ハンドラが同じイベントの消費を取り合うようになったら順序設計が必要。
- **イベントタップのコールバック内で重い処理や再入しうる post を同期実行しない**。重い同期処理は
  タップが `tapDisabledByTimeout` で無効化されイベントを取りこぼし、修飾キーの解放を見逃して
  `leftDown`/`rightDown` が固着しうる（「右⌘が効かない→左⌘を押すと直る」症状）。
  副作用（キー送出など）は `DispatchQueue.main.async` でコールバック復帰後に逃がす（`InputSwitchHandler.fire`）。
- **タップ無効化時はハンドラ状態をリセット**する。`KeyEventTap` は `tapDisabledByTimeout/UserInput` を受けたら
  再有効化に加えて全ハンドラの `reset()` を呼び、取りこぼし後の状態固着を防ぐ。
- **左右⌘の判別は device 依存フラグビット**（`flagsChanged` の `event.flags.rawValue`）で行う:
  左⌘ `0x8`（NX_DEVICELCMDKEYMASK）/ 右⌘ `0x10`（NX_DEVICERCMDKEYMASK）。
- **単押し（`ModifierTapDetector`）は「汚染」で判定**: ⌘押下中に通常キーや他修飾が来たらコンボ扱いで無効化し、
  純粋な押下→解放（しきい時間内）だけを発火させる。これにより `⌘C` 等の通常操作と両立する。
  入力切替は既定で無効（グローバル挙動を変えるため、ユーザーが明示的に有効化）。
- **入力切替は「英数/かなキー送出」方式（TISSelectInputSource は使わない）**。`TISSelectInputSource` は
  「すでに選択中のソースを選び直すと no-op」のため、azooKey 等の複数モードを持つ IME ではモードが切り替わらない
  （成功を返すのに切り替わらない症状）。英数(102)/かな(104)キーは IME へのモード切替コマンドなので、現在の
  選択状態に関係なく確実に切り替わる（Karabiner と同じ方式）。
- **合成キーイベントは `.cghidEventTap`（HID レベル）に post する**。`.cgSessionEventTap` だと IME に届かず
  切り替わらない。HID 相当に post するとハードウェアのキー入力と同様に扱われ、IME も確実に反応する。
- **`Settings` は機能ごとにサブ構造体で分割**し、機能追加は新しいサブ構造体を足す。
  Codable は `decodeIfPresent ?? 既定値` で欠損キーを補完し、旧/新どちらの設定ファイルでも壊れない。
- **設定ダイアログ表示中は Dock アイコンを出す**。`SettingsWindowController` が表示時に
  `NSApp.setActivationPolicy(.regular)`、クローズ時に `.accessory` へ戻す。
- **ログイン項目はシステムが source of truth**。`SMAppService.mainApp` の register/unregister で切り替え、
  状態は `Settings` に保存しない（表示時に `refresh()` で同期）。`.requiresApproval` 時は案内文を出す。
  「一般」タブは設定の Apply/Cancel とは独立に即時反映する。
- **`Settings` の名前衝突**: SwiftUI を import するファイルでは `Settings` が SwiftUI の同名型と
  衝突するため `KeykunCore.Settings` と明示し、SwiftUI 側のバインディングは `@SwiftUI.Binding` と書く。

## 多言語対応（ローカライズ）

GUI に表示する文字列は **日本語・英語の 2 言語に対応**し、OS の優先言語に追従する（既定 `en`）。

- **必須ルール: GUI に文字列を追加・変更したら、必ず多言語対応すること。**
  ハードコードした日本語/英語リテラルを `Text`/`Button`/`NSMenuItem`/`NSAlert`/ウィンドウタイトル/
  HUD 等に直接渡してはいけない。新しい文字列を足すときは:
  1. `Sources/Keykun/Resources/en.lproj/Localizable.strings` と `ja.lproj/Localizable.strings`
     の**両方**にキーと対訳を追加する（キーは `menu.settings` のようなドット区切りの意味ベース）。
  2. コードでは `L.string("キー")`（静的文字列）または `L.format("キー", 値…)`（`%@`/`%d`/`%.1f` 埋め込み）
     で参照する（`Sources/Keykun/Localization.swift`）。
- **仕組み**: `L` はリソースバンドル（`Keykun_Keykun.bundle`）から文字列を解決する。
  SwiftUI/AppKit は既定で `Bundle.main` を見るため、自前で解決して確定済み `String` を渡す。
  `Package.swift` は `defaultLocalization: "en"` と `resources: [.process("Resources")]` を指定済み。
- **`.app` への取り込み**: `Scripts/bundle.sh` が SwiftPM 生成の `Keykun_Keykun.bundle` を
  `Contents/Resources/` にコピーする（これが無いと実行時に文字列が解決できない）。
- **`Info.plist` に `CFBundleLocalizations` が必須**（ハマりどころ）: メインの `Keykun.app` が
  対応言語を宣言していないと、文字列バンドル（`Keykun_Keykun.bundle`）に ja.lproj があっても
  **macOS がアプリ言語を開発リージョン（en）に固定**し、ネストバンドルも en にフォールバックして
  日本語が一切出ない。`Resources/Info.plist` に以下を必ず入れること:
  ```xml
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
  ```
  対応言語を増やしたら、この配列にも言語コードを追加する。
  - 切り分け方: ネストバンドルの ja.lproj を直接 `Bundle(path:)` で開いて
    `localizedString(forKey:value:table:)` が訳文を返すなら文字列ファイルは正常で、原因はこの宣言漏れ。
- **対象外**: アプリ名 `Keykun` や言語非依存な記号、ログ出力（`os.Logger`）は対象外。
- 確認: OS の言語設定を切り替えるか、特定アプリだけ言語を変えて確認する
  （`defaults write com.mtkg.keykun AppleLanguages -array ja` で起動 → 確認後 `defaults delete` で戻す）。

## 開発の進め方

- 純粋ロジック（`KeykunCore`）は **TDD**（テスト先行）で実装する。UI/CGEventTap 連携は手動確認。
- 設定は `~/Library/Application Support/Keykun/settings.json` に保存される。
- 動作確認には実機でのアクセシビリティ権限付与（GUI 操作）が必要。
- **署名**: `Scripts/bundle.sh` は既定で Developer ID Application（Developer Team ID `G72M73C546`）で署名する。
  安定署名にするとアクセシビリティ権限(TCC)が再ビルド後も保持される（アドホック署名は毎回変わり無効化される）。
  `SIGN_IDENTITY` / `TEAM_ID` で上書き、`AD_HOC=1` でアドホック署名に切替可能。
- 機能追加（新しいキー設定）の指針:
  1. 判定ロジックは `KeykunCore` に純粋関数/状態機械として追加し TDD でテスト。
  2. 設定は `Settings` にサブ構造体を足す。
  3. 設定 UI は `SettingsView` の `TabView` にタブを追加する。
  4. 追加した GUI 文字列は必ず en/ja 両方の `Localizable.strings` に対訳を入れる。
