# Sparkle 自動アップデート — セットアップTODO

Verso v0.7.0 では Sparkle 組込み準備のみ。実際の自動アップデート稼働には以下の手順が必要。

## 1. Sparkle Swift Package を追加

`project.yml` に:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    minorVersion: 2.6.0

targets:
  Verso:
    dependencies:
      - package: Sparkle
        product: Sparkle
```

## 2. EdDSA キーペア生成 (一度だけ)

```bash
# Sparkle に同梱されるツール (Swift Package Pluginsから取得)
swift run --package-path .build/checkouts/Sparkle generate_keys
# → 公開鍵 + 秘密鍵が出力される
# 秘密鍵は ~/.local/share/sparkle/private/ に保管 (絶対公開しない)
# 公開鍵は base64 文字列、Info.plist の SUPublicEDKey に貼る
```

## 3. Info.plist (project.yml の info.properties) に追加

```yaml
SUFeedURL: "https://github.com/<username>/verso/releases/latest/download/appcast.xml"
SUPublicEDKey: "<生成された公開鍵base64文字列>"
SUEnableAutomaticChecks: true
SUScheduledCheckInterval: 86400  # 1日に1回チェック
```

## 4. Swift コードに Updater を組込む

`AppDelegate.swift`:

```swift
import Sparkle

let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)

// メニュー項目
NSMenuItem(title: "Check for Updates…",
           action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
           keyEquivalent: "")
    .target = updaterController
```

## 5. GitHub リポジトリ作成

1. プライベートでもOK。GitHub Releases は誰でも DL 可能
2. `verso` という名前で作成
3. Settings → Pages を有効化（appcast.xml ホスト用）

## 6. リリースフロー

```bash
# 1. Tools/build_dmg.sh で DMG 生成
./Tools/build_dmg.sh 0.7.0

# 2. EdDSA で署名 → appcast.xml にサイン情報含める
sign_update dist/Verso-v0.7.0.dmg
# → output: ed25519="<署名base64>"  length="<バイト>"

# 3. appcast.xml を更新（テンプレを別途作成必要）
# 4. GitHub Release 作成 + DMG をアップロード
gh release create v0.7.0 dist/Verso-v0.7.0.dmg \
  --title "Verso v0.7.0" \
  --notes-file CHANGELOG-0.7.0.md

# 5. appcast.xml をコミット & push (Pages がホスト)
git add appcast.xml && git commit -m "release v0.7.0" && git push
```

## 7. 奥さん側

何もしなくてよい:
- Verso が起動中なら 1日1回 SUFeedURL をチェック
- 新版検出 → 通知ダイアログ「v0.7.0 が出ました — Update Now / Later」
- Update Now → ダウンロード + EdDSA 検証 + 自動再起動

## 8. 完成時の体感

| | Before (Sparkle なし) | After (Sparkle あり) |
|---|---|---|
| アップデート通知 | あなたが「新版送るね」と LINE | 自動表示 |
| インストール | 奥さんが DMG 開いて手動コピー | 1クリック |
| 警告 | Gatekeeper警告（自己署名） | 警告なし（EdDSA自動検証） |

## 9. 工数

- **Sparkle SPM追加 + Info.plist + コード組込み**: 30分
- **キー生成 + GitHub repo セットアップ + Pages 有効化**: 30分
- **build_dmg.sh の sign + appcast 更新拡張**: 30分
- **テストリリース → 別Macで自動DL確認**: 30分

合計 ~2時間で「奥さんに渡してから後の運用が完全自動」になる。

## 10. やるタイミング

奥さん渡しの**当日 or 前日**に組むのが良い。早すぎても使わない。
