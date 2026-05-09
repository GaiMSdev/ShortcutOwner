# Changelog

All notable changes to ShortcutOwner are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2025-05-09

### Added
- `SystemShortcutResolver`: detects macOS symbolic hotkeys via Carbon API + plist
- `AppShortcutResolver`: scans menu bar shortcuts in all running apps via Accessibility API
- `CGEventTapResolver`: experimental passive event tap resolver (see README limitations)
- `ShortcutOwner.shared.resolve()`: chains all resolvers with in-memory caching
- `ShortcutOwner.shared.isSystemShortcut()`: zero-permission system shortcut check
- `ShortcutOwner.shared.systemShortcutInfo()`: returns display name for system shortcuts
- `ShortcutOwner.keyName(for:)`: virtual key code → human-readable name
- `ShortcutOwner.shortcutString(keyCode:modifiers:)`: produces display strings like `⌘⇧P`
- Objective-C compatibility throughout (`@objc` surface)
