import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var glossary: Glossary
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var usage: UsageTracker
    @State private var showApiKey: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            languagesTab
                .tabItem { Label("Languages", systemImage: "globe") }

            contextTab
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }

            GlossaryTabView(glossary: glossary)
                .tabItem { Label("Glossary", systemImage: "book") }

            usageTab
                .tabItem { Label("Usage", systemImage: "chart.bar") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 660, height: 560)
        .padding(20)
    }

    // MARK: - General

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    Text("Gemini API Key").font(.headline)
                    Text("Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Group {
                            if showApiKey { TextField("AIza…", text: $settings.apiKey) }
                            else { SecureField("AIza…", text: $settings.apiKey) }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button(showApiKey ? "Hide" : "Show") { showApiKey.toggle() }
                    }
                }

                Divider()

                Group {
                    Text("Model").font(.headline)
                    Picker("", selection: $settings.model) {
                        Text("Gemini 2.5 Flash-Lite — free, fast (1000 RPD)").tag("gemini-2.5-flash-lite")
                        Text("Gemini 2.5 Flash — better quality (250 RPD free)").tag("gemini-2.5-flash")
                        Text("Gemini 2.5 Pro — best, paid tier recommended").tag("gemini-2.5-pro")
                    }
                    .pickerStyle(.menu).labelsHidden()
                }

                Divider()

                Group {
                    Text("DeepL API Key (任意・即時プレビュー用)").font(.headline)
                    Text("登録すると⌘C×2した瞬間にDeepLの即時翻訳が出ます。月50万文字まで無料。Get a free key at [deepl.com/pro-api](https://www.deepl.com/pro-api).")
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("DeepL key (空欄でもOK)", text: $settings.deeplApiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Group {
                    Text("Behavior").font(.headline)
                    Toggle("📌 Stay open after action (popupを自動で閉じない)", isOn: $settings.stayOpen)
                    Toggle("🔒 Privacy mode (履歴に保存しない)", isOn: $settings.privacyMode)
                    Toggle("⚡ 翻訳キャッシュを使う (同じ文章は即時)", isOn: $settings.cacheEnabled)
                    Toggle("📝 Markdown / コード / URL を保持", isOn: $settings.preserveMarkdownAndCode)
                    Toggle("⏸️ Verso を一時停止 (ホットキー無効化)", isOn: $settings.paused)
                }

                Divider()

                Group {
                    Text("Hotkeys").font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("⌘C × 2  →  選択テキストを翻訳").font(.system(.body, design: .monospaced))
                        Text("⌥⇧C    →  画面領域 OCR 翻訳").font(.system(.body, design: .monospaced))
                        Text("⌘⇧H    →  History").font(.system(.body, design: .monospaced))
                        Text("⌘⇧V    →  クリップボード翻訳").font(.system(.body, design: .monospaced))
                    }
                    .font(.system(size: 13)).foregroundColor(.secondary)
                }

                Divider()

                Group {
                    Text("Permissions").font(.headline)
                    HStack {
                        Image(systemName: AccessibilityService.isTrusted()
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(AccessibilityService.isTrusted() ? .green : .orange)
                        Text(AccessibilityService.isTrusted()
                            ? "Accessibility OK" : "Accessibility 未許可 — ホットキー効きません")
                        Spacer()
                        if !AccessibilityService.isTrusted() {
                            Button("Open Settings") {
                                _ = AccessibilityService.checkAndPromptIfNeeded()
                            }
                        }
                    }
                    .font(.system(size: 13))
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Languages

    private var languagesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("デフォルトのターゲット言語")
                .font(.headline)
            Text("自動判定された入力言語に応じて、翻訳先言語を決めます。ポップアップ内で個別に上書きも可能。")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                Text("入力が **英語** のとき → ").frame(width: 200, alignment: .leading)
                Picker("", selection: $settings.targetWhenEnglish) {
                    ForEach(LanguageDetector.availableTargets, id: \.short) {
                        Text("\($0.short)  \($0.fullName)").tag($0.short)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 220)
            }

            HStack {
                Text("入力が **その他** のとき → ").frame(width: 200, alignment: .leading)
                Picker("", selection: $settings.targetWhenOther) {
                    ForEach(LanguageDetector.availableTargets, id: \.short) {
                        Text("\($0.short)  \($0.fullName)").tag($0.short)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 220)
            }

            Divider()

            Text("対応言語の自動判定")
                .font(.headline)
            Text("入力言語は自動判定されます: 日本語(JA) / 英語(EN) / 中国語(ZH) / 韓国語(KO) / スペイン語(ES) / フランス語(FR) / ドイツ語(DE) / イタリア語(IT) / ポルトガル語(PT) / ロシア語(RU)")
                .font(.caption).foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Context

    private var contextTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translator Context").font(.headline)
            Text("プロンプトに毎回注入されるあなた専用のコンテキスト。トーン、ロールプレイ、業界の前提を書く。固有名詞や具体的な訳語は Glossary タブへ。")
                .font(.caption).foregroundColor(.secondary)

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

    // MARK: - Usage

    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API 使用状況").font(.headline)
            Text("Gemini APIのトークン使用量とコスト概算。free tier はカウントされてもコスト$0です。")
                .font(.caption).foregroundColor(.secondary)

            let today = usage.todayStats()
            let month = usage.monthStats()
            let total = usage.allTimeStats()

            VStack(spacing: 0) {
                statRow("Today",      calls: today.calls, tokens: today.tokens, cost: today.cost)
                Divider()
                statRow("This month", calls: month.calls, tokens: month.tokens, cost: month.cost)
                Divider()
                statRow("All time",   calls: total.calls, tokens: total.tokens, cost: total.cost)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("Clear usage history", role: .destructive) {
                    usage.clear()
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding()
    }

    private func statRow(_ label: String, calls: Int, tokens: Int, cost: Double) -> some View {
        HStack {
            Text(label).fontWeight(.medium).frame(width: 110, alignment: .leading)
            Text("\(calls) calls").frame(width: 90, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(tokens) tokens").frame(width: 130, alignment: .leading)
                .foregroundColor(.secondary)
            Text(String(format: "≈ $%.4f", cost)).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundColor(cost > 0.5 ? .orange : .primary)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.vertical, 6)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.bubble").font(.system(size: 56)).foregroundColor(.accentColor)
            Text("Verso").font(.title).bold()
            Text("Personal AI translation, on every page")
                .font(.callout).foregroundColor(.secondary)
            Text("v0.6.0").foregroundColor(.secondary).padding(.top, 4)
            VStack(spacing: 4) {
                Text("⌘C×2  →  選択翻訳")
                Text("⌥⇧C   →  領域OCR翻訳")
                Text("⌘⇧V   →  クリップボード翻訳")
                Text("⌘⇧H   →  履歴")
            }.font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Glossary tab with import/export

struct GlossaryTabView: View {
    @ObservedObject var glossary: Glossary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    exportGlossary()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .disabled(glossary.entries.isEmpty)
                Button {
                    importGlossary()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
            }
            GlossaryView(glossary: glossary)
        }
    }

    private func exportGlossary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "verso-glossary.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(glossary.entries)
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func importGlossary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let imported = try JSONDecoder().decode([GlossaryEntry].self, from: data)

                let alert = NSAlert()
                alert.messageText = "Glossary をインポート"
                alert.informativeText = "\(imported.count) 件のエントリを取り込みます。既存に追加 or 全置換、どちらにしますか？"
                alert.addButton(withTitle: "追加")
                alert.addButton(withTitle: "全置換")
                alert.addButton(withTitle: "キャンセル")
                let resp = alert.runModal()

                if resp == .alertFirstButtonReturn {
                    for e in imported {
                        glossary.add(term: e.term, translation: e.translation,
                                     preserveAsIs: e.preserveAsIs, notes: e.notes)
                    }
                } else if resp == .alertSecondButtonReturn {
                    for e in glossary.entries { glossary.remove(e) }
                    for e in imported {
                        glossary.add(term: e.term, translation: e.translation,
                                     preserveAsIs: e.preserveAsIs, notes: e.notes)
                    }
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
