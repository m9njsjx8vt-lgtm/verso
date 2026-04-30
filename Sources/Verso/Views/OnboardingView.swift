import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var step: Int = 0
    @State private var apiKeyDraft: String = ""
    @State private var deepLDraft: String = ""

    let onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color(NSColor.separatorColor))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            // Step content
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: geminiStep
                    case 2: deepLStep
                    case 3: accessibilityStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }

            // Footer buttons
            Divider()
            HStack {
                if step > 0 {
                    Button("戻る") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Text("\(step + 1) / \(totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(step == totalSteps - 1 ? "完了" : "次へ") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 600, height: 540)
        .onAppear {
            apiKeyDraft = settings.apiKey
            deepLDraft = settings.deeplApiKey
        }
    }

    private func advance() {
        // Save state at the appropriate step
        if step == 1 { settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        if step == 2 { settings.deeplApiKey = deepLDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        if step == totalSteps - 1 {
            onComplete()
        } else {
            step += 1
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.bubble")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Versoへようこそ")
                .font(.largeTitle)
                .bold()
            Text("ハイライトしたテキストを **⌘C×2** で瞬時に翻訳。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "sparkles",
                           title: "AI翻訳 + 即時プレビュー",
                           subtitle: "Gemini で精緻な訳、DeepL で即時プレビュー")
                FeatureRow(icon: "book.closed.fill",
                           title: "用語を学習",
                           subtitle: "Glossary に登録した固有名詞は毎回正しく訳される")
                FeatureRow(icon: "viewfinder",
                           title: "画面OCR翻訳",
                           subtitle: "⌥⇧C で選択した領域のテキストを翻訳")
                FeatureRow(icon: "clock.arrow.circlepath",
                           title: "履歴 + 検索",
                           subtitle: "⌘⇧H でいつでも過去訳を呼び出せる")
            }
            .padding(.top, 8)
        }
    }

    private var geminiStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Gemini APIキー（必須）", systemImage: "key.fill")
                .font(.title2)
                .bold()
            Text("Versoは無料のGemini APIで翻訳します。1分でキーを発行できます:")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1.  下のボタンで Google AI Studio を開く")
                Text("2.  「Get API key」→「Create API key」")
                Text("3.  生成された `AIza...` で始まる文字列をコピー")
                Text("4.  下に貼り付け")
            }
            .font(.callout)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Button {
                if let url = URL(string: "https://aistudio.google.com/apikey") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Google AI Studio を開く", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            SecureField("AIza...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("無料枠: Gemini 2.5 Flash-Lite で 1日約1000回。普段使いには余裕。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var deepLStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("DeepL APIキー（任意）", systemImage: "bolt.fill")
                .font(.title2)
                .bold()
            Text("登録すると ⌘C×2 した瞬間に DeepL の即時プレビューが表示され、その後 Gemini が追いついて精緻版に置き換わります。")
                .font(.body)
                .foregroundColor(.secondary)

            Button {
                if let url = URL(string: "https://www.deepl.com/pro-api") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("DeepL Free を取得", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            SecureField("xxxxxxxx-xxxx-xxxx:fx (空欄でもOK)", text: $deepLDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Text("無料枠: 月50万文字。スキップしても Gemini だけで動きます。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility 権限", systemImage: "lock.shield.fill")
                .font(.title2)
                .bold()
            Text("⌘C×2 と ⌥⇧C を**どこからでも検出**するために、macOS の Accessibility 権限が必要です。")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1.  「完了」ボタンを押すと権限プロンプトが表示されます")
                Text("2.  「システム設定を開く」→ Verso をリストに追加 → トグルON")
                Text("3.  Verso をいったん終了して再起動")
            }
            .font(.callout)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text("Verso はキーストロークを保存・送信しません。⌘C×2 と ⌥⇧C の組み合わせを検出するためだけに使います。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
