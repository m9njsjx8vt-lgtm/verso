# Verso

Personal AI translation, on every page. Select text → ⌘C twice → DeepL-style popup translates it via Gemini.

Built to replace [Nani](https://nani.now) and DeepL with:
- **No usage caps** — uses your own Gemini API key (free tier ≈ 1000 RPD on Flash-Lite)
- **Personal context injection** — teach Verso your tone, glossary, and proper nouns
- **Auto-dismissing popup** that disappears the moment you click anywhere else (DeepL behavior)

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
2. Click the icon → **Settings…**
3. Paste your Gemini API key (get one free at https://aistudio.google.com/apikey)
4. (Optional) Customize the Personalization tab to teach Verso your tone and glossary
5. Grant **Accessibility** permission when prompted (required for ⌘C×2 detection)

## Use

- Select any text in any app
- Press ⌘C twice quickly
- Popup appears near your cursor with the translation
- `Enter` → replace selection with the translation
- `Esc` → dismiss
- Click anywhere else → also dismiss

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
│   └── PasteService.swift      # Sends ⌘V via CGEvent
└── Views/
    ├── PopupController.swift   # Manages popup lifecycle
    ├── PopupWindow.swift       # NSPanel subclass
    ├── PopupView.swift         # SwiftUI popup contents
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
