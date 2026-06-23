# コード署名と公証（Developer ID + notarization）

## なぜ必要か

Keykun はアップデートで `.app` を入れ替えるため、**ビルドごとに署名が変わると
macOS のアクセシビリティ権限 (TCC) が無効化**されます（設定上は有効に見えるのに
⌘Q 二度押しや入力切り替えが効かず、権限を削除→再登録しないと動かない症状）。

これを防ぐには、ビルドをまたいで**同一の安定した署名**で署名します。Apple Developer
Program の **Developer ID Application** 証明書で署名し、さらに **notarization（公証）**
すると、権限が保持されるうえ Gatekeeper の警告も出なくなり、**他人にも配布可能**になります。

リリースは CI（GitHub Actions）が行うため、CI に証明書と公証情報を **Secrets** として
渡します。Secrets 未設定時は ad-hoc 署名（公証なし）にフォールバックします。

このリポジトリのローカルビルド（`bash Scripts/bundle.sh`）は、既定で開発者の
Developer ID Application（Team ID `G72M73C546`）で署名します。CI でも同じ証明書を
Secrets として渡すことで、ローカル/CI を通じて署名が安定します。

---

## 全体の流れ（チェックリスト）

1. [ ] Apple Developer Program に登録（年 $99）
2. [ ] 「Developer ID Application」証明書を作成（Mac のキーチェーンに入る）
3. [ ] その証明書を **`.p12` ファイルに書き出す**
4. [ ] 署名アイデンティティ名・App 用パスワード・Team ID を確認
5. [ ] GitHub に 6 つの Secrets を登録
6. [ ] `main` へ push（バージョンを上げる）→ CI が署名・公証してリリース
7. [ ] 移行の初回のみ、古い権限エントリを削除して再許可

---

## p12 ファイルとは？

**`.p12`（PKCS#12）は「証明書 + 秘密鍵」を 1 つにまとめた持ち運び用ファイル**です。
CI（GitHub Actions のクリーンな Mac）には自分のキーチェーンが無いため、この `.p12` を
Secrets として渡し、CI 側で取り込んで署名に使います。

> ⚠️ `.p12` は秘密鍵を含みます。リポジトリにコミットせず、GitHub Secrets にのみ登録してください。

---

## 手順

### 1. Apple Developer Program に登録

https://developer.apple.com/programs/ から登録（年 $99）。

### 2. Developer ID Application 証明書を作成

Xcode を使うのが簡単です:

1. Xcode > Settings > Accounts に Apple ID を追加
2. 対象チームを選び **Manage Certificates…**
3. 左下 `+` > **Developer ID Application** を作成

作成すると、その証明書（と秘密鍵）が Mac の「ログイン」キーチェーンに入ります。

### 3. 証明書を `.p12` に書き出す

1. **キーチェーンアクセス**.app を開く
2. 「ログイン」キーチェーン >「自分の証明書」カテゴリ
3. `Developer ID Application: あなたの名前 (チームID)` を展開し、
   **証明書と、その下にぶら下がる秘密鍵の両方**を選択
4. 右クリック > **"…" を書き出す…** > フォーマット **個人情報交換 (.p12)**
5. 保存名を `DeveloperID.p12`（任意）にし、**書き出し用パスワード**を設定して保存
   → このパスワードが後述の `SIGNING_CERTIFICATE_PASSWORD`

### 4. 署名名・App 用パスワード・Team ID を確認

- **署名アイデンティティ名**（`SIGNING_IDENTITY`）— ターミナルで確認:
  ```sh
  security find-identity -v -p codesigning
  ```
  `Developer ID Application: Your Name (TEAMID1234)` の形で表示される文字列。

- **Team ID**（`NOTARY_TEAM_ID`）— 上記カッコ内の 10 桁。

- **App 用パスワード**（`NOTARY_PASSWORD`）— https://appleid.apple.com >
  サインインとセキュリティ > **App 用パスワード** で生成（`xxxx-xxxx-xxxx-xxxx`）。

### 5. GitHub Secrets を登録

リポジトリの **Settings > Secrets and variables > Actions > New repository secret** で 6 つ登録:

| Secret 名 | 値 | 取得元 |
|---|---|---|
| `SIGNING_CERTIFICATE_P12_BASE64` | `.p12` を base64 化した文字列 | 下記コマンド |
| `SIGNING_CERTIFICATE_PASSWORD` | `.p12` 書き出し時のパスワード | 手順3 |
| `SIGNING_IDENTITY` | `Developer ID Application: Your Name (TEAMID1234)` | 手順4 |
| `NOTARY_APPLE_ID` | Apple ID（メールアドレス） | あなたの Apple ID |
| `NOTARY_PASSWORD` | App 用パスワード | 手順4 |
| `NOTARY_TEAM_ID` | Team ID（10桁） | 手順4 |

base64 化（`.p12` を 1 行のテキストにしてコピー）:
```sh
base64 -i DeveloperID.p12 | pbcopy
```

> `NOTARY_TEAM_ID` は CI のビルドで `TEAM_ID` としても使われ、`bundle.sh` の署名チェックと
> 公証の Team ID を一致させます。

### 6. push してリリース

Secrets が揃った状態で、`Resources/Info.plist` の `CFBundleShortVersionString` を上げて
`main` へ push すると、リリースワークフローが **Developer ID 署名 → 公証 → staple** して
`v<version>` を作成します。

- `SIGNING_*` のみで `NOTARY_*` が無い → 署名のみ（公証スキップ＝Gatekeeper 警告は残る）
- どちらも無い → ad-hoc 署名（権限は保持されない）

同じ `v<version>` のリリースが既に存在する場合、ワークフローはスキップします
（再リリースするにはバージョンを上げる）。

### 7. 移行時の一回だけの再許可

ad-hoc 版から署名版へ切り替わる初回だけ署名が変わるため:

1. システム設定 > プライバシーとセキュリティ > アクセシビリティ で古い Keykun を削除
2. 新しい版を起動して再度許可

以降、同じ証明書で署名されたアップデートでは権限が保持されます。
