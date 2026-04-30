import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var glossary: Glossary
    @State private var showApiKey: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            contextTab
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }

            GlossaryView(glossary: glossary)
                .tabItem { Label("Glossary", systemImage: "book") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 540)
        .padding(20)
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    Text("Gemini API Key")
                        .font(.headline)
                    Text("Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Group {
                            if showApiKey {
                                TextField("AIza…", text: $settings.apiKey)
                            } else {
                                SecureField("AIza…", text: $settings.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button(showApiKey ? "Hide" : "Show") { showApiKey.toggle() }
                    }
                }

                Divider()

                Group {
                    Text("Model")
                        .font(.headline)
                    Picker("", selection: $settings.model) {
                        Text("Gemini 2.5 Flash-Lite — free, fast (1000 RPD)").tag("gemini-2.5-flash-lite")
                        Text("Gemini 2.5 Flash — better quality (250 RPD free)").tag("gemini-2.5-flash")
                        Text("Gemini 2.5 Pro — best, paid tier recommended").tag("gemini-2.5-pro")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                Group {
                    Text("DeepL API Key (任意・即時プレビュー用)")
                        .font(.headline)
                    Text("登録すると、⌘C×2した瞬間にDeepLの即時翻訳が出て、その後Geminiが追いついて精緻版に置き換わります。無料枠は月50万文字。Get a free key at [deepl.com/pro-api](https://www.deepl.com/pro-api).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("DeepL key (空欄でもOK)", text: $settings.deeplApiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Group {
                    Text("Hotkeys")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("⌘C × 2").font(.system(.body, design: .monospaced))
                            Text("→ 選択テキストを翻訳").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("⌥⇧C").font(.system(.body, design: .monospaced))
                            Text("→ 画面領域をOCRして翻訳").foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 13))
                }

                Divider()

                Group {
                    Text("Permissions")
                        .font(.headline)
                    HStack {
                        Image(systemName: AccessibilityService.isTrusted()
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill")
                            .foregroundColor(AccessibilityService.isTrusted() ? .green : .orange)
                        Text(AccessibilityService.isTrusted()
                            ? "Accessibility OK — ホットキー検出可能"
                            : "Accessibility 未許可 — ホットキーが効きません")
                        Spacer()
                        if !AccessibilityService.isTrusted() {
                            Button("Open Settings") {
                                _ = AccessibilityService.checkAndPromptIfNeeded()
                            }
                        }
                    }
                    .font(.system(size: 13))

                    Text("OCR (⌥⇧C) は初回実行時に Screen Recording 権限を要求します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Context

    private var contextTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translator Context")
                .font(.headline)
            Text("プロンプトに毎回注入されるあなた専用のコンテキスト。トーン、ロールプレイ、業界の前提を書く。固有名詞や具体的な訳語は Glossary タブへ。")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $settings.translatorContext)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Reset to default") {
                    settings.translatorContext = AppSettings.defaultContext
                }
                .controlSize(.small)
            }
        }
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.bubble")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("Verso")
                .font(.title)
                .bold()
            Text("Personal AI translation, on every page")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("v0.5.0")
                .foregroundColor(.secondary)
                .padding(.top, 4)
            VStack(spacing: 4) {
                Text("⌘C×2  →  選択テキスト翻訳")
                Text("⌥⇧C  →  画面領域OCR翻訳")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
