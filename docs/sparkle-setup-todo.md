# Sparkle 自動アップデート — 残作業チェック

Verso v0.9.0 時点で、Sparkle の基本組み込みは完了済み。

- Sparkle Swift Package: `project.yml` に追加済み
- `SPUStandardUpdaterController`: `AppDelegate.swift` に追加済み
- `SUFeedURL`: `https://m9njsjx8vt-lgtm.github.io/verso/appcast.xml`
- `SUPublicEDKey`: `project.yml` / `Generated-Info.plist` に設定済み
- GitHub Pages: `main:/docs` で `docs/appcast.xml` を配信
- 公開リリース: `v0.8.0`, `v0.9.0`

今は Tomoro 本人利用を優先する。別ユーザー向けの追加導線や説明は、渡す直前に別途作る。

## いま残っていること

### 1. 配布ビルド用の署名環境

`Tools/build_dmg.sh` は配布用に `Verso Self-Signed` 署名証明書を要求する。

```bash
security find-identity -v -p codesigning | grep "Verso Self-Signed"
```

見つからない場合:

- 本人利用のデバッグ起動: `./script/build_and_run.sh --verify`
- DMG配布: 証明書を作成/importしてから `./Tools/build_dmg.sh`

### 2. リリースごとの手順

1. `project.yml` の `CFBundleShortVersionString` と `CFBundleVersion` を上げる
2. `./Tools/build_dmg.sh <version>` を実行
3. 出力された `sparkle:edSignature` と `length` を `docs/appcast.xml` に追加
4. GitHub Release に `dist/Verso-v<version>.dmg` を添付
5. `docs/appcast.xml` を push
6. GitHub Pages 反映後に appcast を確認

```bash
curl https://m9njsjx8vt-lgtm.github.io/verso/appcast.xml
```

### 3. 将来のDeveloper ID対応

今の `Verso Self-Signed` は本人利用・検証用。広く配る段階では:

- Apple Developer Program に登録
- Developer ID Application 証明書で署名
- Hardened Runtime を有効化
- notarization を追加

## 完成判定

本人利用では、以下が満たされれば十分:

- `./script/build_and_run.sh --verify` が通る
- `verso://settings` が開く
- `⌘C×2`, `⌘⇧T`, `⌥⇧C` が落ちずに動く
- Local AI が `Test Local AI` で通る
- Local AI 失敗時、翻訳ポップアップから `Start Ollama` / `Open LM Studio` で復旧できる
- DeepL APIキーなしでもオンボーディングを完了できる

配布準備では、追加で以下が必要:

- `./Tools/build_dmg.sh <version>` が成功する
- GitHub Release からDMGをダウンロードできる
- `docs/appcast.xml` の新 `<item>` が実DMGと一致する
- Sparkle の更新確認で新版が検出される
