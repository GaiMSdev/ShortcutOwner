import Foundation
import AppKit
import ApplicationServices

@objc public class AppShortcutResolver: NSObject, ShortcutResolver {
    @objc public var requiresAccessibilityPermission: Bool { true }

    private var hasPermissionChecked = false
    private var cachedPermission = false

    public override init() {
        super.init()
    }

    @objc public var hasPermission: Bool {
        if !hasPermissionChecked {
            cachedPermission = AXIsProcessTrusted()
            hasPermissionChecked = true
        }
        return cachedPermission
    }

    @objc public func supportsAccessibility() -> Bool {
        return true
    }

    @objc public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        completion: @escaping (ShortcutOwnerResult?) -> Void
    ) {
        if !hasPermission {
            completion(nil)
            return
        }

        // Search in all running applications with a regular activation policy
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            
            var menuBar: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
            
            if result == .success, let menuBarElement = menuBar as! AXUIElement? {
                if let foundElement = findMenuItem(in: menuBarElement, keyCode: keyCode, modifiers: modifiers) {
                    var title: AnyObject?
                    AXUIElementCopyAttributeValue(foundElement, kAXTitleAttribute as CFString, &title)
                    
                    completion(ShortcutOwnerResult(
                        bundleIdentifier: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "Unknown App",
                        shortcutTitle: title as? String,
                        shortcutDescription: "Menu Item Shortcut",
                        category: .app,
                        isSystemShortcut: false
                    ))
                    return
                }
            }
        }

        completion(nil)
    }

    private func findMenuItem(in element: AXUIElement, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> AXUIElement? {
        var children: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        guard result == .success, let childrenArray = children as? [AXUIElement] else {
            return nil
        }

        for child in childrenArray {
            // Check if this child matches the shortcut
            if isMatch(element: child, keyCode: keyCode, modifiers: modifiers) {
                return child
            }
            
            // Recursively search in children
            if let found = findMenuItem(in: child, keyCode: keyCode, modifiers: modifiers) {
                return found
            }
        }
        
        return nil
    }

    private func isMatch(element: AXUIElement, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        var cmdChar: AnyObject?
        var cmdMods: AnyObject?
        
        let charResult = AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &cmdChar)
        let modsResult = AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &cmdMods)
        
        guard charResult == .success, modsResult == .success,
              let charStr = cmdChar as? String,
              let modsInt = cmdMods as? Int else {
            return false
        }
        
        // Convert virtual key code to character for comparison
        let keyChar = character(for: keyCode)
        
        // Convert AX mods to NSEvent.ModifierFlags
        // AX modifiers: 0=cmd, 1=shift, 2=opt, 3=ctrl (bitmask)
        var axMods: NSEvent.ModifierFlags = []
        axMods.insert(.command) // Command is implicit for all menu shortcuts
        if (modsInt & 1) != 0 { axMods.insert(.shift) }
        if (modsInt & 2) != 0 { axMods.insert(.option) }
        if (modsInt & 4) != 0 { axMods.insert(.control) }
        
        // The AX modifier bitmask is often: 0=none (Cmd implied), 1=Shift, 2=Option, 4=Control
        // So we normalize our target modifiers to compare
        let targetMods = modifiers.intersection([.command, .shift, .option, .control])
        
        // Basic match check (case-insensitive for character)
        return charStr.lowercased() == keyChar.lowercased() && axMods.contains(.command) == targetMods.contains(.command)
    }

    private func character(for keyCode: UInt16) -> String {
        // Simplified mapping for common shortcut keys
        // In a real app, use TISCopyCurrentKeyboardLayoutInputSource and UCKeyTranslate
        switch keyCode {
        case 0: return "a"; case 1: return "s"; case 2: return "d"; case 3: return "f"
        case 4: return "h"; case 5: return "g"; case 6: return "z"; case 7: return "x"
        case 8: return "c"; case 9: return "v"; case 11: return "b"; case 12: return "q"
        case 13: return "w"; case 14: return "e"; case 15: return "r"; case 16: return "y"
        case 17: return "t"; case 31: return "o"; case 32: return "u"; case 34: return "i"
        case 35: return "p"; case 37: return "l"; case 38: return "j"; case 40: return "k"
        case 45: return "n"; case 46: return "m"
        default: return ""
        }
    }
}
