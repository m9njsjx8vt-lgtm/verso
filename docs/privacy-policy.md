# Verso — プライバシーポリシー

Last updated: 2026-05-14

Verso (以下「本アプリ」) は Tomoro Iwasaki が個人開発する macOS アプリケーションです。本ポリシーは本アプリがどのようにユーザーデータを扱うかを説明します。

## 1. 収集・送信するデータ

本アプリ自体は**ユーザーデータをいかなる第三者にも収集・送信しません**。

ただし、ユーザーが翻訳機能を実行した場合、入力テキストは以下のサードパーティ翻訳API（ユーザーが設定したもの）にのみ送信されます:

- **Google AI Studio (Gemini API)** — 翻訳本体
  - https://policies.google.com/privacy
- **DeepL API** (任意) — 即時プレビュー
  - https://www.deepl.com/privacy

これらのAPIへの送信内容・利用条件は各サービスのプライバシーポリシーに従います。本アプリ開発者は中継サーバーを持たず、これらの通信を傍受・記録しません。

## 2. ローカル保存データ

以下はユーザーのMac内のみに保存され、本アプリ開発者を含めいかなる第三者にも送信されません。

| データ | 場所 | 用途 |
|---|---|---|
| API キー（Gemini, DeepL） | `~/Library/Application Support/Verso/secrets.json` (mode 0600) | API認証 |
| 翻訳履歴 | `~/Library/Application Support/Verso/history.json` | 履歴検索・再利用 |
| 用語集 (Glossary) | `~/Library/Application Support/Verso/glossary.json` | 翻訳プロンプト注入 |
| 使用統計 (トークン数) | `~/Library/Application Support/Verso/usage.json` | コスト確認 |
| 翻訳コンテキスト | macOS UserDefaults | 翻訳プロンプト注入 |

## 3. ユーザーが取れる対応

- **履歴を残さない**: Settings → Behavior → Privacy mode を ON
- **履歴を消す**: Settings → Usage タブ、または手動でファイル削除
- **API キーを削除**: Settings → General で空欄にする
- **すべて消去**: `~/Library/Application Support/Verso/` ディレクトリを削除

## 4. システム権限

本アプリは以下のmacOS権限を要求します:

| 権限 | 目的 |
|---|---|
| **Accessibility** | ⌘C×2 / ⌥⇧C / ⌘⇧V / ⌘⇧H のグローバルホットキー検出。**キーストロークの記録・送信は行いません**（特定のキー組み合わせのみ反応） |
| **Screen Recording** | ⌥⇧C のOCR翻訳機能で、ユーザーが選択した画面領域を一時的にキャプチャ。キャプチャ画像は OCR 処理後すぐに破棄され保存されません |
| **Apple Events** | 翻訳結果を ⌘V で他アプリに貼り付けるため |

すべての権限はユーザーが System Settings → Privacy & Security でいつでも取り消せます。

## 5. 子ども・未成年

本アプリは13歳未満を対象としていません。

## 6. 変更履歴

このポリシーは将来更新される可能性があります。重大な変更があった場合は本アプリ内通知またはアップデートリリースノートで告知します。

## 7. 連絡先

質問は Tomoro Iwasaki まで。
