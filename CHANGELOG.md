# Changelog

All notable changes to ShortcutOwner are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.1] - 2026-05-09

### Fixed
- `AppShortcutResolver.isMatch()`: removed broken `(modsInt & 0) == 0` check that always evaluated to true, causing Command modifier to be inserted unconditionally. Command is now correctly treated as implicit for all AX menu item shortcuts per the Accessibility API specification.

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
