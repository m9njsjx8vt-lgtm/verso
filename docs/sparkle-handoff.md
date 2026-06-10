# Sparkle 自動アップデート — 運用メモ

Current state (2026-06-10):

- GitHub repo: `https://github.com/m9njsjx8vt-lgtm/verso` is public.
- GitHub Pages source: `main:/docs`.
- Live appcast: `https://m9njsjx8vt-lgtm.github.io/verso/appcast.xml`.
- Releases `v0.8.0`〜`v0.10.0` are publicly downloadable.
- `Verso Self-Signed` code-signing identity: created on this Mac (2026-06-10),
  lives in the dedicated keychain `~/Library/Keychains/verso-signing.keychain-db`
  (registered in the user keychain search list; valid until 2036).
- Sparkle EdDSA key: **regenerated on this Mac for v0.10.0** (the original key
  stayed on the old Mac). Private key is in the login keychain AND exported to
  `~/.local/share/sparkle/private/verso_eddsa_key` (chmod 600) so `sign_update
  --ed-key-file` works non-interactively. Consequence: installs of v0.9.0 and
  older cannot auto-update across the key change — install v0.10.0 manually
  from the DMG once; auto-update works from v0.10.0 onward.
- `xcodegen` is NOT installed on this Mac; the scripts use the checked-in
  `Verso.xcodeproj`, so version bumps must be made in BOTH `project.yml` and
  `Sources/Verso/Generated-Info.plist` (PlistBuddy) until xcodegen is installed.

Verso v0.9.0 時点で Sparkle SPM dependency、Updater、EdDSA公開鍵、
`SUFeedURL`、GitHub Pages appcast hosting は設定済み。

次回以降のリリース毎に必要なのは:

1. `project.yml` の version/build number 更新
2. `Verso Self-Signed` 証明書がある環境で DMG 作成
3. `sign_update` 出力を `docs/appcast.xml` に追加
4. GitHub Release 作成
5. `docs/appcast.xml` を push して Pages 反映確認

実時間 ~1.5時間 (内 GitHub操作・確認多め)。

---

## Step 1 — Sparkle CLIツールを取得

```bash
# Xcode が SPM経由で Sparkle を fetch する間、CLIバイナリも同梱される
cd ~/Projects/Translator
xcodebuild -scheme Verso -configuration Release -destination 'platform=macOS' -derivedDataPath ./build build

# generate_keys と sign_update がここに
ls ./build/SourcePackages/artifacts/sparkle/Sparkle/bin/
# →  generate_keys, sign_update
```

PATH に通すと楽:
```bash
export PATH="$HOME/Projects/Translator/build/SourcePackages/artifacts/sparkle/Sparkle/bin:$PATH"
```

---

## Step 2 — EdDSA キーペア生成 (一度だけ)

```bash
generate_keys
```

出力例:
```
A key has been generated and saved in your keychain. Add the public key to your Sparkle host configuration:

SUPublicEDKey
<BASE64_PUBLIC_KEY_HERE>
```

- **秘密鍵**は macOS Keychain に保存される (Sparkle CLI が自動)。**絶対に export/共有しない**
- **公開鍵** (base64文字列) を `project.yml` の `SUPublicEDKey` に貼る

```bash
# project.yml を編集
sed -i '' 's|REPLACE_ME_BASE64_EDDSA_PUBLIC_KEY|<貼り付け>|' project.yml
```

---

## Step 3 — GitHub リポ + Pages を準備

```bash
cd ~/Projects/Translator
gh repo create verso --private --source=. --push   # Private でも Releases は誰でも DL可
# → https://github.com/<username>/verso

# Pages を有効化 (appcast.xml ホスト用)
gh repo edit --enable-pages --pages-branch main --pages-path /docs
```

`SUFeedURL` を実URLに置換:
```bash
sed -i '' 's|https://example.com/REPLACE_ME/appcast.xml|https://<username>.github.io/verso/appcast.xml|' project.yml
```

---

## Step 4 — appcast.xml の初版を作成

`docs/appcast.xml` を作る:

```xml
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Verso</title>
    <description>Most recent changes</description>
    <language>ja</language>
    <!-- 各リリースを <item> として追加していく -->
  </channel>
</rss>
```

コミット & push:
```bash
git add docs/appcast.xml && git commit -m "Init Sparkle appcast"
git push
```

数分後 `https://<username>.github.io/verso/appcast.xml` でアクセス可能になる。

---

## Step 5 — `Tools/build_dmg.sh` を Sparkle 対応に拡張

既存の `build_dmg.sh` の末尾に追記:

```bash
echo "▸ Signing DMG with Sparkle EdDSA key..."
SIGNATURE_OUTPUT=$(sign_update "$DMG_PATH")
echo "$SIGNATURE_OUTPUT"
# 出力例: sparkle:edSignature="..." length="..."

echo ""
echo "▸ NEXT STEPS:"
echo "1. Add a new <item> to docs/appcast.xml using the signature above"
echo "2. git add docs/appcast.xml && git commit -m 'release v$VERSION' && git push"
echo "3. gh release create v$VERSION $DMG_PATH --title 'Verso v$VERSION'"
```

---

## Step 6 — リリースフロー (毎回)

```bash
# 1. version 上げる (project.yml の CFBundleShortVersionString)
# 2. CHANGELOG 書く
# 3. ビルド + 署名
./Tools/build_dmg.sh 0.9.0
# → dist/Verso-v0.9.0.dmg + sparkle:edSignature 出力

# 4. appcast.xml に <item> 追加
cat >> docs/appcast.xml.snippet <<EOF
<item>
  <title>v0.9.0</title>
  <pubDate>$(date -R)</pubDate>
  <sparkle:version>12</sparkle:version>             <!-- CFBundleVersion -->
  <sparkle:shortVersionString>0.9.0</sparkle:shortVersionString>
  <description><![CDATA[
    <ul>
      <li>新機能 A</li>
      <li>バグ修正 B</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://github.com/<username>/verso/releases/download/v0.9.0/Verso-v0.9.0.dmg"
    sparkle:edSignature="<上で出力された署名>"
    length="<DMGサイズ in bytes>"
    type="application/octet-stream" />
</item>
EOF
# (上の snippet を docs/appcast.xml の <channel> の中に手動で挿入)

# 5. GitHub Release 作成
gh release create v0.9.0 dist/Verso-v0.9.0.dmg \
  --title "Verso v0.9.0" \
  --generate-notes

# 6. appcast push
git add docs/appcast.xml && git commit -m "release v0.9.0" && git push
```

---

## Step 7 — 将来の引き渡し先側

何もしなくていい:
- Verso 起動中に 1日1回 `SUFeedURL` をチェック
- 新版検出 → 「Verso v0.9.0 が出ました — Update Now / Later」
- Update Now → DL → EdDSA 検証 → 自動再起動

---

## チェックリスト

- [ ] `generate_keys` 実行、`SUPublicEDKey` を `project.yml` に貼った
- [ ] GitHub repo 作成、Pages 有効化
- [ ] `SUFeedURL` を実URLに置換
- [ ] `docs/appcast.xml` 初版コミット
- [ ] `build_dmg.sh` を Sparkle 対応に拡張
- [ ] テストリリース (v0.8.1) を作って自分のMacで自動DLが動くか確認
- [ ] OK なら引き渡し先に DMG URL を送る (初回だけ手動)

---

## トラブル

| 症状 | 原因 / 対処 |
|---|---|
| "Update is improperly signed" | `SUPublicEDKey` の置換忘れ、または `sign_update` し忘れ |
| "No update available" なのに新版あるはず | appcast.xml のキャッシュ。1時間待つか `Check for Updates` 強制 |
| 「Check for Updates…」メニューが出ない | `SUFeedURL` がまだ `REPLACE_ME` のまま。AppDelegate がガードしてる |
| `generate_keys` が見つからない | Step 1 のパスで CLI 取得 / `brew install sparkle` でも入る |
