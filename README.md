# Clipboard — Native macOS Clipboard Manager

A beautiful, fast, privacy-first clipboard manager for macOS, built with Swift, SwiftUI, and AppKit.

Clipboard keeps your recent copied content available from anywhere with a global keyboard shortcut, so you can quickly find, preview, and reuse anything you've copied.

Local-first. No cloud sync. No account. No telemetry. Your clipboard history stays on your Mac.

## ✨ Features

### 🚀 Fast Clipboard History

- Continuously monitors the macOS clipboard using NSPasteboard
- Stores clipboard history locally
- Supports text, URLs, images, rich text, and file URLs where supported
- Prevents duplicate clipboard entries using content hashing
- Designed to remain lightweight while running in the background

### ⌨️ Global Keyboard Shortcut

Open your clipboard from anywhere using:

```
⌘ ⇧ V
```

The shortcut works even when another application is focused.

Navigate with:

```
↑ / ↓     Navigate
Enter     Select
Esc       Close
⌘ P       Pin / Unpin
⌘ Delete  Delete
```

The global hotkey is implemented at the application level rather than being tied to a SwiftUI view lifecycle.

### 🔎 Instant Search

Search your clipboard history immediately after opening the clipboard window.

For example:

```
github
```

can quickly find:

```
https://github.com/...
github.com/openai/...
git clone ...
```

The interface is designed around a keyboard-first workflow.

### 🖼️ Multiple Clipboard Types

Clipboard items can represent different types of content:

- 📝 Plain text
- 🌐 URLs
- 🖼️ Images
- 📄 Rich text / HTML / RTF
- 📁 File URLs

Images can be displayed with thumbnails, while text and URLs receive appropriate previews.

### 📌 Pin Important Items

Frequently used clipboard items can be pinned so they remain easy to access.

Example:

```
📌 Pinned

API endpoint
Common code snippet
Frequently used command
Email template
```

Pinned items are protected from automatic history cleanup.

### 🔒 Privacy & Sensitive Data Protection

Clipboard contents can contain sensitive information such as:

- Passwords
- OTP codes
- API keys
- JWTs
- Credit-card-like numbers
- Private keys
- Authentication tokens

The application includes sensitive-content detection and privacy controls.

Users can configure options such as:

```
☑ Don't store sensitive clipboard items
☑ Automatically delete OTP codes
☑ Ignore password-manager clipboard content
☑ Pause clipboard history
☑ Automatically delete old history
```

Sensitive content should not be exposed unnecessarily in previews or logs.

### 💾 Local Storage

Clipboard history is stored locally using SQLite.

The application does not require:

- An account
- A backend
- Internet access
- Cloud synchronization

Large binary content such as images should be stored efficiently rather than loading everything into the database at once.

## 🎨 UI

The application is designed as a native macOS utility inspired by the interaction patterns of Spotlight, Raycast, Alfred, and modern macOS applications.

The main clipboard interface looks conceptually like:

```
┌─────────────────────────────────────────────┐
│ 🔍  Search clipboard...                    │
├─────────────────────────────────────────────┤
│                                             │
│  Today                                      │
│                                             │
│  🌐  https://github.com/openai/...          │
│      2 minutes ago                          │
│                                             │
│  📝  func authenticateUser() async ...      │
│      5 minutes ago                          │
│                                             │
│  📝  Hello, this is a clipboard item...     │
│      12 minutes ago                         │
│                                             │
│  🖼️  Screenshot                             │
│      20 minutes ago                         │
│                                             │
└─────────────────────────────────────────────┘
```

The UI supports:

- Light mode
- Dark mode
- macOS materials
- Rounded corners
- Subtle animations
- Keyboard navigation
- Image thumbnails
- Context menus
- Empty states
- Loading states
- Toast/confirmation feedback

## 🖥️ Menu Bar App

Clipboard runs primarily as a macOS menu bar utility.

The menu bar menu provides quick access to:

```
Clipboard

Open Clipboard        ⌘⇧V

Recent
────────────────────
Last copied item
Second item
Third item

────────────────────
Pause History
Clear History
Settings...
Quit
```

The application is designed to behave like a native background utility rather than a traditional document-based macOS application.

## 🏗️ Architecture

The project follows a modular architecture separating UI, clipboard access, persistence, global hotkeys, and application services.

```
ClipboardApp/
│
├── App/
│   ├── ClipboardApp.swift
│   └── AppController.swift
│
├── Clipboard/
│   ├── ClipboardMonitor.swift
│   ├── ClipboardReader.swift
│   ├── ClipboardWriter.swift
│   └── ClipboardContent.swift
│
├── Storage/
│   ├── Database.swift
│   ├── ClipboardRepository.swift
│   └── ClipboardItem.swift
│
├── Hotkey/
│   └── GlobalHotKey.swift
│
├── Services/
│   ├── ClipboardService.swift
│   ├── SearchService.swift
│   └── SensitiveDataDetector.swift
│
├── UI/
│   ├── ClipboardWindow.swift
│   ├── ClipboardView.swift
│   ├── ClipboardSearchBar.swift
│   ├── ClipboardItemRow.swift
│   ├── ClipboardPreview.swift
│   └── SettingsView.swift
│
└── Utilities/
    ├── AppConstants.swift
    └── Extensions.swift
```

### Architecture Overview

```
                 macOS NSPasteboard
                         │
                         ▼
                ┌─────────────────┐
                │ ClipboardMonitor│
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ ClipboardService│
                └────────┬────────┘
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
        Sensitive Detector      SHA-256 Hash
              │                     │
              └──────────┬──────────┘
                         ▼
                  SQLite Database
                         │
                         ▼
                  Search Service
                         │
                         ▼
                  SwiftUI Interface
                         ▲
                         │
                  Global Hotkey
                    ⌘ ⇧ V
```

## 🧰 Technology Stack

| Technology | Purpose |
|---|---|
| Swift | Application language |
| SwiftUI | User interface |
| AppKit | macOS-specific functionality |
| NSPasteboard | Clipboard access |
| SQLite | Local clipboard history |
| Carbon / RegisterEventHotKey | Global keyboard shortcut |
| SMAppService | Launch at login |
| CryptoKit | Content hashing |
| macOS Accessibility APIs | Optional automatic paste behavior |

## 🔐 Privacy Model

Clipboard is intentionally designed as a local-first application.

```
Copied Content
      │
      ▼
NSPasteboard
      │
      ▼
Sensitive Data Detection
      │
      ├── Sensitive ──► Local-only / Ignore
      │
      └── Normal
            │
            ▼
       Local SQLite
```

There is:

- ❌ No cloud backend
- ❌ No analytics
- ❌ No telemetry
- ❌ No external API calls
- ❌ No clipboard data sent to third-party services

Clipboard contents remain on the user's Mac.

## ⚡ Performance Goals

Clipboard should remain almost invisible while running.

The implementation aims for:

- Low CPU usage
- Low memory usage
- Efficient clipboard monitoring
- Background database operations
- Lazy image loading
- Limited large-payload handling
- Fast search
- No unnecessary network activity
- No UI blocking during database operations

The clipboard monitor should avoid unnecessarily aggressive polling.

## ♿ Accessibility & Permissions

Automatic pasting into the previously active application may require macOS Accessibility permission.

If permission is unavailable:

- Clipboard still works normally.
- The selected item is copied to the system clipboard.
- The user can paste it manually with ⌘V.
- The app can guide the user to the appropriate macOS System Settings page.

The application should never become unusable simply because Accessibility permission was not granted.

## ⚙️ Settings

The settings interface is organized into:

**General**
- Launch at Login
- Global Shortcut
- Show Menu Bar Icon

**Clipboard**
- Maximum history size
- Automatic cleanup
- Save images
- Save files

**Privacy**
- Sensitive-content detection
- Ignore OTPs
- Ignore password-manager content
- Pause clipboard history
- Automatic deletion

**Appearance**
- Follow System
- Light
- Dark

**About**
- Application version
- Privacy information
- Project information

## 🚧 Current Scope

This project intentionally focuses on local clipboard management.

**Included**

- Native macOS application
- Menu bar integration
- Clipboard monitoring
- Local clipboard history
- SQLite persistence
- Global keyboard shortcut
- Search
- Keyboard navigation
- Pinning
- Duplicate detection
- Image support
- URL support
- File URL support
- Privacy controls
- Sensitive-content detection
- Dark/light appearance
- Launch at login
- Accessibility-aware paste behavior

**Not Included**

- iCloud / CloudKit synchronization
- Cross-Mac clipboard synchronization
- iPhone/iPad companion app
- Cloud backup
- User accounts
- Server-side storage

The project deliberately keeps clipboard history local in this version.

## 🚀 Getting Started

### Requirements

- macOS 14.0 or later
- Xcode 15+
- Swift 5.9+
- Apple Silicon or Intel Mac

### Clone

```bash
git clone https://github.com/ujjwaltiwariii/clippy.git
cd clippy
```

### Build & Run from Xcode

```bash
open clippy.xcodeproj
```

Then press `⌘R` in Xcode to build and run.

### Build & Install from the Terminal

Build a release version of the app using `xcodebuild`:

```bash
xcodebuild -project clippy.xcodeproj \
  -scheme clippy \
  -configuration Release \
  -derivedDataPath build \
  clean build
```

Copy the built app into your `/Applications` folder:

```bash
cp -R build/Build/Products/Release/clippy.app /Applications/
```

Launch the app:

```bash
open /Applications/clippy.app
```

On first launch, macOS Gatekeeper may block the unsigned/locally-built app. If so, either:

- Right-click `clippy.app` in Finder → **Open** → confirm **Open**, or
- Remove the quarantine attribute from the terminal:

```bash
xattr -dr com.apple.quarantine /Applications/clippy.app
```

To open the clipboard manager, use the global shortcut `⌘⇧V`, or click the menu bar icon.

### Uninstall

```bash
# Quit the app first, then:
rm -rf /Applications/clippy.app
```

## 🧪 Development

The application can be developed and tested entirely offline.

Recommended development flow:

```
Run App
   ↓
Copy text / image / URL
   ↓
Clipboard Monitor detects change
   ↓
Content is classified
   ↓
Sensitive data check
   ↓
Duplicate check
   ↓
SQLite persistence
   ↓
⌘⇧V
   ↓
Search / select
   ↓
Copy / paste
```

## 🗺️ Roadmap

### v0.1

- Native macOS menu bar application
- Clipboard monitoring
- Local persistence
- Global shortcut
- Search
- Keyboard-first UI

### v0.2

- Better image handling
- File clipboard support
- Pinning
- History cleanup
- Improved previews
- Sensitive-content detection

### v0.3

- Advanced search
- Better accessibility
- More keyboard shortcuts
- Performance improvements
- Improved settings

### Future

Potential future versions may explore:

- iCloud/CloudKit synchronization
- iPhone/iPad companion
- Cross-device clipboard history
- Advanced content categorization

These features are not part of the current version.

## 🤝 Contributing

Contributions are welcome.

Before opening a pull request:

- Keep the application native to macOS.
- Avoid unnecessary dependencies.
- Do not introduce network services for clipboard data.
- Keep sensitive clipboard data out of logs.
- Maintain the separation between UI, storage, and system services.
- Test keyboard navigation and clipboard behavior carefully.

## 🔒 Security

If you discover a security or privacy issue, please avoid publicly posting sensitive clipboard-related details.

Open a private security report or contact the project maintainer directly.

## 📄 License

Add your preferred license here.

For example: MIT License

## ⭐ Project Philosophy

Clipboard should be:

> Fast enough to disappear, powerful enough to remember everything you need, and private enough to trust.

Built specifically for macOS with a focus on:

**Native UX · Keyboard-first workflow · Privacy · Performance · Simplicity**
