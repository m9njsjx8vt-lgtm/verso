# Tomo (友)

Your translation companion. Select text → ⌘C twice → DeepL-style popup translates it via Gemini API.

Built to replace [Nani](https://nani.now) and DeepL with:
- **No usage caps** (uses your own Gemini API key, free tier ≈ 1000 RPD on Flash-Lite)
- **Personal context injection** — teach it your tone, glossary, and proper nouns
- **Auto-dismissing popup** that disappears the moment you click anywhere else (DeepL behavior)

## Build & Run

```bash
brew install xcodegen           # one-time
cd ~/Projects/Translator
xcodegen                        # generates Tomo.xcodeproj
xcodebuild -scheme Tomo -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./build build
open ./build/Build/Products/Debug/Tomo.app
```

Or open in Xcode:

```bash
xcodegen && open Tomo.xcodeproj
```

## First-time setup

1. Launch the app — a 🔤 icon appears in the menu bar
2. Click the icon → **Settings…**
3. Paste your Gemini API key (get one free at https://aistudio.google.com/apikey)
4. (Optional) Customize the Personalization tab to teach Tomo your tone and glossary
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
Sources/Tomo/
├── TranslatorApp.swift         # @main, app entry
├── AppDelegate.swift           # Menu bar + lifecycle
├── Models/
│   └── Settings.swift          # AppSettings: UserDefaults + Keychain
├── Services/
│   ├── KeychainService.swift   # API key storage (com.tomoro.tomo)
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
swift Tools/make_icon.swift /tmp/icon.png 友   # any single character
Tools/build_icns.sh /tmp/icon.png Sources/Tomo/Resources/AppIcon.icns
xcodegen && xcodebuild -scheme Tomo -configuration Debug -destination 'platform=macOS' -derivedDataPath ./build build
```
