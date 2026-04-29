import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @State private var showApiKey: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            contextTab
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 520)
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
                    Text("Permissions")
                        .font(.headline)
                    HStack {
                        Image(systemName: AccessibilityService.isTrusted()
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill")
                            .foregroundColor(AccessibilityService.isTrusted() ? .green : .orange)
                        Text(AccessibilityService.isTrusted()
                            ? "Accessibility OK — ⌘C×2 detection works"
                            : "Accessibility not granted — ⌘C×2 won't work")
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

    // MARK: - Context

    private var contextTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translator Context")
                .font(.headline)
            Text("This text is injected into every translation prompt. Teach the translator your tone, glossary, and proper nouns.")
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
                    settings.translatorContext = Settings.defaultContext
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
            Text("Translator")
                .font(.title)
                .bold()
            Text("v0.1.0")
                .foregroundColor(.secondary)
            Text("⌘C×2 で日英翻訳ポップアップ")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
