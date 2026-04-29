# Translator

A native macOS menu-bar app: select text → press ⌘C twice → DeepL-style popup translates it via Gemini API.

Built to replace [Nani](https://nani.now)/DeepL with:
- **No usage caps** (uses your own Gemini API key, free tier = 1000 RPD on Flash-Lite)
- **Personal context injection** — teach it your tone, glossary, and proper nouns
- **Auto-dismissing popup** that disappears the moment you click anywhere else (DeepL behavior)

## Build & Run

```bash
brew install xcodegen           # one-time
cd ~/Projects/Translator
xcodegen                        # generates Translator.xcodeproj
xcodebuild -scheme Translator -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/Translator.app
```

Or open in Xcode:

```bash
xcodegen && open Translator.xcodeproj
```

## First-time setup

1. Launch the app — a 🔤 icon appears in the menu bar
2. Click the icon → **Settings…**
3. Paste your Gemini API key (get one free at https://aistudio.google.com/apikey)
4. (Optional) Customize the Personalization tab to teach the translator your tone/glossary
5. Grant **Accessibility** permission when prompted (required for ⌘C×2 detection)

## Use

- Select any text in any app
- Press ⌘C twice quickly
- Popup appears near your cursor with the translation
- `Enter` → replace selection with translation
- `Esc` → dismiss
- Click anywhere else → also dismiss

## Project structure

```
Sources/Translator/
├── TranslatorApp.swift         # @main, app entry
├── AppDelegate.swift           # Menu bar + lifecycle
├── Models/
│   └── Settings.swift          # UserDefaults + Keychain wrapper
├── Services/
│   ├── KeychainService.swift   # API key storage
│   ├── AccessibilityService.swift
│   ├── HotkeyMonitor.swift     # ⌘C×2 detection (NSEvent global monitor)
│   ├── GeminiClient.swift      # Gemini API wrapper (URLSession + async/await)
│   └── PasteService.swift      # Sends ⌘V via CGEvent
└── Views/
    ├── PopupController.swift   # Manages popup lifecycle
    ├── PopupWindow.swift       # NSPanel subclass
    ├── PopupView.swift         # SwiftUI popup contents
    └── SettingsView.swift      # SwiftUI Settings window
```
