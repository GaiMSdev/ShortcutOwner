import Foundation
import AppKit

/// Main entry point for the ShortcutOwner library.
/// Provides a unified API for looking up which app owns a given keyboard shortcut.
@objc public class ShortcutOwner: NSObject {
    @objc public static let shared = ShortcutOwner()

    private let systemResolver = SystemShortcutResolver()
    private let appResolver = AppShortcutResolver()
    private let eventTapResolver = CGEventTapResolver()

    private var cache = [String: ShortcutOwnerResult]()

    @objc public override init() {
        super.init()
    }

    /// Looks up which app owns a keyboard shortcut.
    /// Tries resolvers in order: System -> App -> CGEventTap.
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code (e.g. 35 for "P").
    ///   - modifiers: The modifier flags (e.g. .command.union(.shift)).
    ///   - completion: Called with the result, or nil if no owner found.
    public func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        completion: @escaping (ShortcutOwnerResult?) -> Void
    ) {
        let cacheKey = "\(keyCode)-\(modifiers.rawValue)"
        if let cachedResult = cache[cacheKey] {
            completion(cachedResult)
            return
        }

        systemResolver.resolve(keyCode: keyCode, modifiers: modifiers) { [weak self] result in
            if let result = result {
                self?.cache[cacheKey] = result
                completion(result)
                return
            }
            self?.appResolver.resolve(keyCode: keyCode, modifiers: modifiers) { result in
                if let result = result {
                    self?.cache[cacheKey] = result
                    completion(result)
                    return
                }
                self?.eventTapResolver.resolve(keyCode: keyCode, modifiers: modifiers) { result in
                    if let result = result {
                        self?.cache[cacheKey] = result
                    }
                    completion(result)
                }
            }
        }
    }

    /// Convenience overload for Objective-C callers.
    @objc public func resolve(
        keyCode: UInt16,
        modifiers rawModifiers: Int,
        completion: @escaping (ShortcutOwnerResult?) -> Void
    ) {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawModifiers))
        resolve(keyCode: keyCode, modifiers: modifiers, completion: completion)
    }

    /// Returns whether a system shortcut matches the given keyCode + modifiers.
    /// This is a synchronous, zero-permission check suitable for use in Safari extensions.
    @objc public func isSystemShortcut(keyCode: UInt16, modifiers rawModifiers: Int) -> Bool {
        return systemResolver.isSystemShortcut(keyCode: keyCode, rawModifiers: rawModifiers)
    }

    /// Returns a description of the system shortcut for display, or nil.
    @objc public func systemShortcutInfo(keyCode: UInt16, modifiers rawModifiers: Int) -> String? {
        return systemResolver.systemShortcutTitle(keyCode: keyCode, rawModifiers: rawModifiers)
    }

    /// Checks if Input Monitoring permission is granted.
    @objc public var hasInputMonitoringPermission: Bool {
        return eventTapResolver.hasPermission
    }

    /// Checks if Accessibility permission is granted.
    @objc public var hasAccessibilityPermission: Bool {
        return appResolver.hasPermission
    }

    /// Requests Input Monitoring permission (opens System Settings).
    @objc public func requestInputMonitoringPermission() {
        eventTapResolver.requestPermission()
    }

    /// Requests Accessibility permission (opens System Settings).
    @objc public func requestAccessibilityPermission() {
        appResolver.requestPermission()
    }

    /// Clears the in-memory cache. Call this when the user changes system shortcut settings
    /// so the next resolve() re-scans rather than returning a stale cached result.
    @objc public func clearCache() {
        cache.removeAll()
    }

    /// Converts a macOS VK keycode to a human-readable key name.
    @objc public static func keyName(for keyCode: UInt16) -> String {
        return KeyCodeMap.keyName(for: keyCode)
    }

    /// Converts modifier flags to a display string like "⌘⇧P".
    @objc public static func shortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }
}

/// Maps macOS virtual key codes to human-readable names.
enum KeyCodeMap {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape", 54: "Right ⌘", 55: "⌘",
        56: "⇧", 57: "CapsLock", 58: "⌥", 59: "⌃", 60: "Right ⇧",
        61: "Right ⌥", 62: "Right ⌃", 63: "fn",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 118: "F4", 119: "F2", 120: "F1", 121: "F16",
        122: "F17", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        return names[keyCode] ?? "Key\(keyCode)"
    }

    /// Converts Carbon modifier flags (cmdKeyBit, etc.) to NSEvent.ModifierFlags.
    static func carbonToModifiers(_ carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonMods & 0x100) != 0 { flags.insert(.command) }
        if (carbonMods & 0x200) != 0 { flags.insert(.shift) }
        if (carbonMods & 0x400) != 0 { flags.insert(.option) }
        if (carbonMods & 0x800) != 0 { flags.insert(.control) }
        return flags
    }

    /// Converts NSEvent.ModifierFlags to Carbon modifier flags.
    static func modifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= 0x100 }
        if flags.contains(.shift)   { carbon |= 0x200 }
        if flags.contains(.option)  { carbon |= 0x400 }
        if flags.contains(.control) { carbon |= 0x800 }
        return carbon
    }
}
