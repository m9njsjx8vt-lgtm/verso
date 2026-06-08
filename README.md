# Verso

Personal AI translation, on every page. Select text → ⌘C twice → DeepL-style popup translates it via Gemini or a local AI model.

Built to replace [Nani](https://nani.now) and DeepL with:
- **Cloud or offline translation** — use Gemini, or switch to local Ollama / OpenAI-compatible servers
- **Personal context injection** — teach Verso your tone, glossary, and proper nouns
- **Auto-dismissing popup** that disappears the moment you click anywhere else (DeepL behavior)
- **Workspace mode** — keep a regular translation window open for longer text and edits
- **Translation styles** — switch between direct business, casual, polished, literal, and MBA English modes

## Build & Run

```bash
cd ~/Projects/translator
./script/build_and_run.sh --verify
```

The script uses full Xcode from `/Applications/Xcode.app` when available,
builds into `./build`, launches the freshly built app, and falls back to an
unsigned Debug build when the local `Verso Self-Signed` certificate is missing.

Install XcodeGen when you want to regenerate the project from `project.yml`:

```bash
brew install xcodegen
xcodegen
```

Or open the generated project in Xcode:

```bash
xcodegen && open Verso.xcodeproj
```

## First-time setup

1. Launch the app — a 🔤 icon appears in the menu bar
2. In the welcome tour, choose **Gemini** or **Local AI**
3. For Gemini, paste your API key (get one free at https://aistudio.google.com/apikey), or skip and add it later
4. For Local AI, use **Start Ollama** or **Open LM Studio**, then **Refresh Models** and **Test Local AI**
5. (Optional) Add a DeepL API key for instant preview
6. Grant **Accessibility** permission when prompted (required for ⌘C×2 detection)
7. Later, use **Settings → General → AI Engine** to change providers or models

## Local AI / offline mode

Verso defaults to **Local AI** for offline-first personal use, and can translate without internet access when **AI Engine** is set to **Local AI**.

- Ollama default endpoint: `http://localhost:11434`
- Default local model on Tomoro's machine: `huihui_ai/qwen3-abliterated:14b`
- LM Studio / llama.cpp servers: choose **OpenAI Compatible** and use a `/v1` endpoint such as `http://localhost:1234/v1`
- Settings can open LM Studio directly, or start `ollama serve` when the Ollama CLI is installed
- Use **Refresh Models** in Settings to discover installed local models and choose one
- Use **Test Local AI** in Settings to confirm the endpoint/model before relying on offline translation
- If Gemini is selected but the Mac is offline, Verso falls back to Local AI for that request
- DeepL preview remains cloud-only and will show as unavailable while offline

## Use

### Popup

- Select any text in any app
- Press ⌘C twice quickly
- Popup appears near your cursor with the translation
- `Enter` → replace selection with the translation
- `Esc` → dismiss
- Click anywhere else → also dismiss

### Workspace

- Press `⌘⇧T` or choose **Open Workspace** from the menu bar
- Paste or type longer text
- Choose a target language and translation style
- Press `⌘↵` to translate inline
- Copy the result, send the same source text to the popup, or use the result as the next source text

## Project structure

```
Sources/Verso/
├── TranslatorApp.swift         # @main, app entry
├── AppDelegate.swift           # Menu bar + lifecycle
├── Models/
│   └── Settings.swift          # AppSettings: UserDefaults + Keychain
├── Services/
│   ├── KeychainService.swift   # API key storage (com.tomoro.verso)
│   ├── AccessibilityService.swift
│   ├── HotkeyMonitor.swift     # ⌘C×2 detection (NSEvent global monitor)
│   ├── GeminiClient.swift      # Gemini API wrapper (URLSession + async/await)
│   ├── LocalAIClient.swift     # Ollama / OpenAI-compatible local AI wrapper
│   └── PasteService.swift      # Sends ⌘V via CGEvent
└── Views/
    ├── PopupController.swift   # Manages popup lifecycle
    ├── PopupWindow.swift       # NSPanel subclass
    ├── PopupView.swift         # SwiftUI popup contents
    ├── WorkspaceWindowController.swift # Persistent inline translation window
    ├── HistoryView.swift       # Searchable translation history
    └── SettingsView.swift      # Settings window (General / Personalization / About)

Tools/
├── make_icon.swift             # Core Graphics icon generator
└── build_icns.sh               # sips/iconutil pipeline
```

## Regenerate icon

```bash
# Default: Georgia-Bold serif "V" at 760pt (matches the Verso brand)
swift Tools/make_icon.swift /tmp/icon.png V "Georgia-Bold" 760
Tools/build_icns.sh /tmp/icon.png Sources/Verso/Resources/AppIcon.icns
./script/build_and_run.sh --verify
```

## Release

Current Sparkle feed:
https://m9njsjx8vt-lgtm.github.io/verso/appcast.xml

To build a distributable DMG, import or create the `Verso Self-Signed` signing
identity first, then run:

```bash
./Tools/build_dmg.sh 0.9.1
```

## Naming

**Verso** — Latin/Italian for *verse* or *the back of a page*. Bookish and refined; evokes language and the printed word without being a literal "translator" name.
