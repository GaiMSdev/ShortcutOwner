# ShortcutOwner

A Swift library for macOS that answers the question: **"Which app owns this keyboard shortcut?"**

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue.svg)](https://developer.apple.com/macos/)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/GaiMSdev/ShortcutOwner/actions/workflows/ci.yml/badge.svg)](https://github.com/GaiMSdev/ShortcutOwner/actions/workflows/ci.yml)

---

## What it does

When building a macOS app that lets users record custom keyboard shortcuts, you want to warn them if the shortcut is already in use — and ideally tell them *by whom*. ShortcutOwner gives you that.

```swift
ShortcutOwner.shared.resolve(keyCode: 49, modifiers: .command) { result in
    if let result = result {
        print("\(result.appName): \(result.shortcutTitle ?? "Unknown")")
        // "System Settings: Spotlight"
    }
}
```

---

## Features

- **System shortcuts** — reads `com.apple.symbolichotkeys.plist` directly; no private API required for detection
- **App menu shortcuts** — scans all running apps via Accessibility API
- **Zero-permission fast path** — `isSystemShortcut` checks the plist without any permissions
- **In-memory caching** — repeated lookups don't re-scan
- **Objective-C compatible** — full `@objc` surface for mixed codebases
- **Open-source and auditable** — no black boxes

---

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GaiMSdev/ShortcutOwner.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repo URL.

---

## Usage

### Quick check — is it a system shortcut?

No permissions required. Reads the user's plist directly.

```swift
import ShortcutOwner

let taken = ShortcutOwner.shared.isSystemShortcut(keyCode: 49, modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
// true → Spotlight
```

### Full resolution — who owns it?

```swift
ShortcutOwner.shared.resolve(keyCode: 35, modifiers: [.command, .shift]) { result in
    guard let result = result else {
        print("Shortcut is free")
        return
    }
    print("Owned by: \(result.appName)")
    print("Title: \(result.shortcutTitle ?? "—")")
    print("System: \(result.isSystemShortcut)")
}
```

### Cache invalidation

ShortcutOwner caches results in memory. If the user may have changed shortcuts (e.g. visited System Settings), clear the cache before resolving:

```swift
ShortcutOwner.shared.clearCache()
ShortcutOwner.shared.resolve(keyCode: 35, modifiers: [.command, .shift]) { result in
    // fresh result
}
```

### Display-ready strings

```swift
let keyName = ShortcutOwner.keyName(for: 35)      // "P"
let display = ShortcutOwner.shortcutString(keyCode: 35, modifiers: [.command, .shift])  // "⌘⇧P"
```

---

## Resolvers

ShortcutOwner chains three resolvers in order:

| Resolver | What it checks | Permission required |
|---|---|---|
| `SystemShortcutResolver` | macOS symbolic hotkeys (`com.apple.symbolichotkeys.plist`) + Carbon API | None |
| `AppShortcutResolver` | Menu bar shortcuts in all running regular apps via AX API | Accessibility |
| `CGEventTapResolver` | ⚠ Experimental — see below | Input Monitoring |

### `SystemShortcutResolver`

Reads the user's actual keyboard shortcut preferences. Combines two sources:
1. Carbon's `CopySymbolicHotKeys()` for the active set
2. `~/Library/Preferences/com.apple.symbolichotkeys.plist` for symbolic IDs (used to look up names)

Returns the shortcut name from Apple's `DefaultShortcutsTable.xml` when available.

### `AppShortcutResolver`

Walks the menu bar of every running `.regular`-policy app via `AXUIElement`. Requires Accessibility permission (`AXIsProcessTrusted()`). Prompt the user before calling:

```swift
if !ShortcutOwner.shared.hasAccessibilityPermission {
    ShortcutOwner.shared.requestAccessibilityPermission()
}
```

### `CGEventTapResolver` ⚠ Experimental

Installs a passive `CGEventTap` and waits up to 3 seconds for the shortcut to be pressed. **Current limitations:**
- Requires Input Monitoring permission
- Identifies the *focused* app at the time of the keypress, not necessarily the one that registered the hotkey
- Background hotkey owners (e.g. menu bar apps) are invisible to this resolver
- Not suitable for production use as-is; included for future investigation

---

## Permissions

| Feature | Required permission |
|---|---|
| System shortcut detection | None |
| System shortcut name lookup | None |
| App menu shortcut scanning | Accessibility |
| CGEventTap resolution | Input Monitoring |

For sandboxed apps, Accessibility permission is granted by the user in **System Settings → Privacy & Security → Accessibility**. Input Monitoring is similarly under Privacy & Security.

---

## `ShortcutOwnerResult`

```swift
public class ShortcutOwnerResult {
    public let bundleIdentifier: String      // "com.apple.Spotlight"
    public let appName: String               // "Spotlight"
    public let shortcutTitle: String?        // "Show Spotlight Search"
    public let shortcutDescription: String?  // Category or description
    public let category: ShortcutCategory    // .system / .app / .accessibility
    public let isSystemShortcut: Bool
}
```

---

## Requirements

- macOS 12.0+
- Swift 5.9+
- Xcode 15+

---

## Contributing

Pull requests welcome. Please:
- Keep changes focused — one fix or feature per PR
- Add or update tests in `Tests/ShortcutOwnerTests/`
- Run `swift test` before submitting
- For new resolvers, document permission requirements and known limitations

---

## License

MIT. See [LICENSE](LICENSE).
