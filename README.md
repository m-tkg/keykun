# Keykun

macOS 用のキー操作カスタマイズツール（メニューバー常駐アプリ）。
第一の機能は **「安全な Quit」** ＝ `⌘Q` を **2回押さないとアプリが終了しない** ようにするもので、
Karabiner-Elements の「Quit application by pressing command-q twice」設定と同じ挙動を、
Karabiner なしの単独アプリで実現します。今後さまざまなキー設定機能を追加していく前提の構成です。

## 仕組み（安全な Quit）

`CGEventTap` で `keyDown` を横取りし、

1. **1回目の `⌘Q`** … イベントを握りつぶし、HUD「もう一度 ⌘Q で終了」を表示
2. **判定時間内の2回目の `⌘Q`** … そのまま通す（＝最前面のアプリが終了）
3. **タイムアウト** … 解除して通常状態へ戻る

判定そのもの（状態機械）は AppKit/CGEventTap に依存しない純粋ロジック `KeykunCore.DoublePressDecider`
に切り出してあり、単体テスト可能です。修飾キーは `command` のみを対象とし、`caps lock` は無視します。

## 設定

メニューバーの `⌘` アイコン →「設定…」で**設定ダイアログ**を開きます（表示中は Dock にも出ます）。
設定はタブで分かれており、現状は「**安全な Quit**」タブに以下があります。

- 有効 / 無効
- 判定時間（0.5 / 1.0 / 1.5 / 2.0 秒）

設定は `~/Library/Application Support/Keykun/settings.json` に保存されます。
今後のキー機能はタブを追加する形で増やしていきます。

### 入力切り替え（左右 ⌘ 単押し）

「**入力切り替え**」タブで、**左 ⌘ / 右 ⌘ を単独で押して離す**（他キーと一緒に押さない）と、
割り当てた入力ソース（例: 左＝ABC、右＝日本語）に切り替わります。`⌘C` などの組み合わせでは
通常どおり修飾キーとして機能し、**単押しのときだけ**切り替えが発火します（長押しでも発火しません）。

- 左 ⌘ / 右 ⌘ それぞれに、macOS で有効化済みの入力ソースを割り当て
- 既定は**無効**（グローバル挙動を変えるため、明示的に有効化して使用）
- 「単押し」の判定: ⌘押下〜解放の間に他キーが無く、一定時間（既定 0.3 秒）以内に離した場合

## 多言語対応

GUI は **日本語・英語**に対応し、OS の優先言語に追従します（既定 `en`）。
文字列は `Sources/Keykun/Resources/{en,ja}.lproj/Localizable.strings` に定義し、`L.string` / `L.format` で参照します。
詳細・追加ルールは [CLAUDE.md](CLAUDE.md) を参照。

## 構成

テスト可能なコアとアプリ本体を SwiftPM で分離しています（snapperkun と同様の構成）。

```
Sources/
  KeykunCore/               純粋ロジック（テスト対象）
    DoublePressDecider.swift   ⌘Q 二度押し判定の状態機械
    ModifierTapDetector.swift  左右⌘の単押し検知
    Settings.swift             設定モデル（機能ごとにサブ構造体）
    SettingsStore.swift        JSON 永続化
  Keykun/                   アプリ本体
    main.swift / AppDelegate.swift
    KeyEventTap.swift           CGEventTap を共有し各ハンドラへ配信
    SafeQuitHandler.swift       安全な Quit（⌘Q 二度押し）
    InputSwitchHandler.swift    入力切り替え（左右⌘単押し）
    InputSourceService.swift    Carbon TIS で入力ソース列挙・切替
    AccessibilityPermission.swift
    StatusBarController.swift   メニュー（入口のみ）
    SettingsWindowController.swift / SettingsView.swift   設定ダイアログ（TabView）
    HUDController.swift
    Localization.swift          L ヘルパー
    Resources/{en,ja}.lproj/Localizable.strings
Tests/KeykunCoreTests/      DoublePressDecider / ModifierTapDetector / Settings / SettingsStore のテスト
Resources/Info.plist        バンドル情報（LSUIElement で Dock 非表示）
Scripts/bundle.sh           .app 生成 + 署名
```

## ビルド・テスト

```sh
swift test                 # コアロジックのテスト
bash Scripts/bundle.sh     # Keykun.app を生成（既定: release + Developer ID 署名）
```

### 署名

`Scripts/bundle.sh` は既定で **Developer ID Application（Developer Team ID: `G72M73C546`）** で署名します。
**安定署名にすることで、再ビルドしても付与済みのアクセシビリティ許可（TCC）が保持されます**。

| 変数 | 既定 | 用途 |
|---|---|---|
| `SIGN_IDENTITY` | `Developer ID Application: Masaki TAKAGI (G72M73C546)` | codesign の署名アイデンティティ |
| `TEAM_ID` | `G72M73C546` | Developer Team ID |
| `AD_HOC=1` | （無効） | 証明書が無い環境向けにアドホック署名へ切替 |

## インストール / リリース

ビルド済みアプリは [Releases](../../releases) から `Keykun.zip` をダウンロードできます。
解凍して `/Applications` に置いて起動してください。

リリースは GitHub Actions（`.github/workflows/release.yml`）が自動化しています。
`Resources/Info.plist` の `CFBundleShortVersionString` を上げて `main` へ push すると、
`v<version>` のリリースが作成されます（同一バージョンのリリースが既にあればスキップ）。
配布用の Developer ID 署名・公証の設定は [docs/SIGNING.md](docs/SIGNING.md) を参照してください
（Secrets 未設定時は ad-hoc 署名でリリースされます）。

## 使い方

1. `open Keykun.app` で起動
2. 初回はアクセシビリティの許可を求められます
   「システム設定 › プライバシーとセキュリティ › アクセシビリティ」で **Keykun** を許可
   （許可後は再起動不要で自動的に有効になります）
3. メニューバーの `⌘` アイコン →「設定…」で動作を調整できます

`/Applications` に置いて使う場合は `cp -r Keykun.app /Applications/` でコピーしてください。
