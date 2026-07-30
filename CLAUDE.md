# CLAUDE.md — keykun

このリポジトリで作業する際のガイド。

**メニューバー常駐アプリ（kun シリーズ）共通の方針は上位ディレクトリの [`../kun-template/CLAUDE_base.md`](../kun-template/CLAUDE_base.md) を参照**
（Swift Package 構成・日英ローカライズ・アップデート・ログイン項目・ローカルビルド／公証・kunkit 連携・
リリース手順・ブランチ運用など）。共通方針を変えるときは `CLAUDE_base.md`
（[kun-template](https://github.com/m-tkg/kun-template) が canonical）を編集する。
本ファイルには keykun 固有の事項のみを記す。

---

# keykun 固有事項

**概要**: macOS 用のキー操作カスタマイズツール（メニューバー常駐アプリ）。bundle ID は `com.mtkg.keykun`。
外部依存なし（AppKit / ApplicationServices / SwiftUI のみ）の Swift Package Manager プロジェクトで、
ターゲットは `KeykunCore`（純粋ロジック）＋ `Keykun`（App）。今後さまざまなキー設定機能を追加する前提で、
設定 UI はタブで拡張する構成にしている。

## 機能
- **安全な Quit**: `⌘Q` を2回押さないとアプリを終了させない（Karabiner の「command-q を2回押して終了」相当を
  Karabiner なしで実現）。1回目は握りつぶして「もう一度 ⌘Q で終了」HUD を出し、猶予時間内の2回目で通す。
- **入力ソース切替**: 左右 Command の単押し（長押しでない・他キー併用なし）で英数／かなを切り替える
  （既定は無効。ユーザーが明示的に有効化する）。

## コマンド
```sh
swift build                            # ビルド
swift test                             # 全テスト
swift test --filter DoublePressDeciderTests   # 個別テスト
swift run                              # 直接実行（開発時）
bash Scripts/bundle.sh                 # .app バンドル生成（既定 release + Developer ID 署名）
LOCAL=1 bash Scripts/bundle.sh debug   # ローカル検証ビルド（本番と権限を分離。詳細は base のセクション7・8）
make release-tag                       # main 最新で v<version> タグを push（CI がリリース）
make beta-tag                          # v<version>-beta.<N> タグを push（CI が pre-release として公開）
```

## アーキテクチャ

2 ターゲット構成。**純粋ロジックとプラットフォーム依存を分離**しているのが要点。

- **`KeykunCore`（ライブラリ / テスト対象）**: AppKit/CGEventTap に依存しないロジックとモデル。
  - `DoublePressDecider` — ⌘Q 二度押し判定の状態機械。時刻を `now`（単調増加秒）として注入する純粋ロジック。
    1回目は `.consumeAndArm`（握りつぶし）、猶予時間内の2回目は `.passThrough`（通す）を返す。
  - `ModifierTapDetector` — 左右 Command の「単押し」検知の純粋ロジック。`commandDown`/`commandUp`/`contaminate`
    を時刻注入で受け、単押し成立時に `ModifierSide` を返す。
  - `Settings` / `SafeQuitSettings` / `InputSwitchSettings` — 設定モデル。機能ごとにサブ構造体を持ち、
    機能追加で拡張する。Codable は欠損キーを既定値で補完する（前方/後方互換）。
- **`Keykun`（実行ファイル）**: CGEventTap / AppKit / SwiftUI 連携と UI。
  - `main.swift` — `NSApplication` 起動（`.accessory`、`MainActor.assumeIsolated`）。多重起動防止は kunkit の
    `KunAppLaunch.terminateIfAlreadyRunning()`。
  - `AppDelegate` — 設定読込・各部品の配線・権限取得（`@MainActor`）。設定永続化は kunkit の
    `KunSettingsStore<Settings>`（`~/Library/Application Support/Keykun/settings.json`）。
  - `KeyEventTap` — CGEventTap を1つだけ生成し、`keyDown` と `flagsChanged` を購読して登録された複数の
    `KeyEventHandler` へ配信する。いずれかが消費要求したらイベントを握りつぶす。
  - `SafeQuitHandler`（`KeyEventHandler`）— ⌘Q を抽出して `DoublePressDecider` に委譲。
    1回目は握りつぶし HUD 表示、2回目は通してアプリを終了させる。
  - `InputSwitchHandler`（`KeyEventHandler`）— `flagsChanged` から左右⌘の押下/解放を device 依存ビットで判定し、
    `ModifierTapDetector` に委譲。単押し成立時に `InputModeKey.post` で英数/かなキーを送出する（イベントは消費しない）。
  - `InputModeKey` — 英数(102)/かな(104)キーの CGEvent を `.cghidEventTap`（HID 相当）に post して IME のモードを切り替える。
  - `AccessibilityPermission` — アクセシビリティ権限の確認・要求・設定画面オープン。
  - `StatusBarController` — メニューバー常駐メニュー（入口のみ。設定項目は設定ダイアログに集約）。
  - `SettingsWindowController` / `SettingsView` — SwiftUI の設定ダイアログ。タブで機能ごとに分割。
    ログイン項目は kunkit の `LoginItemController`（`SMAppService.mainApp`）で「一般」タブから即時反映する。
  - `HUDController` — 「もう一度 ⌘Q で終了」HUD。
  - `UpdateService` — 最新リリース取得（kunkit `GitHubReleaseFetcher`）。自己更新は kunkit の `SelfUpdater`。

データの流れ:
キー入力 → `KeyEventTap`（CGEventTap）が各ハンドラへ配信 →
`SafeQuitHandler` は ⌘Q を `DoublePressDecider` に渡し `.consumeAndArm` なら消費・`.passThrough` なら通す /
`InputSwitchHandler` は左右⌘の単押しを `ModifierTapDetector` で判定し成立時に英数/かなキーを送出する。

## 設計上の重要な前提（変更時に注意）

CGEventTap を使うため、以下の固有知見は最重要。壊すと間欠的なキー固着・入力切替不能を招く。

- **二度押し判定はコア層（`DoublePressDecider`）に閉じ込め、CGEventTap 非依存に保つ**。
  時刻は呼び出し側から注入し、テスト可能にする。アプリ側（`SafeQuitHandler`）は単調増加時計
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
- **修飾キー二度押しの押下判定は `ModifierFlagsInterpreter`（KeykunCore）で行う**。device 依存ビットは
  非公式で、Caps Lock→Control リマップ（システム設定/hidutil）環境ではビットが立たない `flagsChanged` が
  来ることがあり、ビットだけ見ると押下遷移を観測できず無反応になる（「別の Mac で ctrl 二度押しが効かない」症状）。
  そのため keyCode（どのキーが変化したかの一次情報）を主として「device ビット → generic mask
  （`.maskControl` 等の device 非依存フラグ）→ 内部追跡状態のトグル」の3段判定で down/up を決める。
  Caps Lock（keyCode 57）は generic の control mask がそのイベントで新たに立ったときのみ「左 Control の押下」
  として扱い、通常のトグル（alphaShift のみ）は無視する。
- **単押し（`ModifierTapDetector`）は「汚染」で判定**: ⌘押下中に通常キーや他修飾が来たらコンボ扱いで無効化し、
  純粋な押下→解放（しきい時間内）だけを発火させる。これにより `⌘C` 等の通常操作と両立する。
- **入力切替は「英数/かなキー送出」方式（TISSelectInputSource は使わない）**。`TISSelectInputSource` は
  「すでに選択中のソースを選び直すと no-op」のため、azooKey 等の複数モードを持つ IME ではモードが切り替わらない
  （成功を返すのに切り替わらない症状）。英数(102)/かな(104)キーは IME へのモード切替コマンドなので、現在の
  選択状態に関係なく確実に切り替わる（Karabiner と同じ方式）。
- **合成キーイベントは `.cghidEventTap`（HID レベル）に post する**。`.cgSessionEventTap` だと IME に届かず
  切り替わらない。HID 相当に post するとハードウェアのキー入力と同様に扱われ、IME も確実に反応する。
- **`Settings` の名前衝突**: SwiftUI を import するファイルでは `Settings` が SwiftUI の同名型と
  衝突するため `KeykunCore.Settings` と明示し、SwiftUI 側のバインディングは `@SwiftUI.Binding` と書く。

## Kuntraykun 連携（実装済み・kunkit 利用）

本アプリは kuntraykun（`com.mtkg.kuntraykun`）にメニューバーアイコンを集約させる連携（v1〜v4:
アイコン集約・実アイコン書き出し・アップデート集約・サブメニュー表示）に対応している。
- **実装は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit)**（SPM 依存、`KunIntegrationBridge` プロダクト）。
  `KuntraykunBridge` / `KuntraykunIconExport` / `KuntraykunMenuExport` を提供し、アプリ側に連携ロジックの複製は持たない。
- 配線: `StatusBarController.makeKuntraykunBridge()`（`KuntraykunBridge(statusItem:menu:)` の標準配線）を
  `AppDelegate` が `bridge.start()` する。start() が観測開始・`appLaunched` 送信・初回メニュー書き出しまで行う。
  アイコン書き出し（v2）は `StatusBarController` init の `KuntraykunIconExport.export(_:)`、
  アップデート報告（v3）は `kuntraykunBridge?.reportUpdate(_:)`、
  メニュー文言の変化（v4）は `statusBar.onMenuContentChanged` → `bridge.exportMenuSnapshot()`（表示中は自動保留）。
- 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`、共通方針は `../kun-template/CLAUDE_base.md`「Kuntraykun 連携」。
- 管理対象フラグは kunkit が `UserDefaults`（キー `KuntraykunManaged`）に永続化する。
- **kunkit 由来の共通実装**: 自己更新（`SelfUpdater`）・ログイン項目（`LoginItemController`）・多重起動防止（`KunAppLaunch`、`main.swift`）・設定永続化（`KunSettingsStore`）・外部プロセス実行（`ProcessRunner`）・更新チェック（`GitHubReleaseFetcher` / `ReleaseInfo` / `VersionComparator` / `KunUpdateSchedule` / `ReleaseDownloader`）は kunkit（`KunAppKit` / `KunSupport` / `KunUpdateKit`）が提供する。アプリ側に複製は持たず、アプリ名・文言・repo は注入する。
- **kunkit の更新運用**: 連携プロトコルの変更・修正は kunkit 側（TDD）で行って semver タグを発行し、
  各アプリは `swift package update kunkit` で追従する（`from: "1.0.0"` 指定のため 1.x は自動追従、
  破壊的変更はメジャーを上げる）。本リポジトリは `Package.resolved` を非追跡（CI ビルドが最新 1.x を解決する）。
- **連携のデバッグ**: まず `~/Library/Application Support/Kuntraykun/Menus/<基底ID>.json` の中身
  （空なら書き出し側の問題）と、Console の subsystem `com.mtkg.keykun` / category `kuntraykun` の
  ログを確認する。
