import Foundation
import AppKit
import Carbon

@_silgen_name("CopySymbolicHotKeys")
private func CopySymbolicHotKeys(_ hotKeysRef: UnsafeMutablePointer<Unmanaged<CFArray>?>?) -> OSStatus

private let noErr: OSStatus = 0

@objc public class SystemShortcutResolver: NSObject, ShortcutResolver {
    private var symbolicHotKeys: [(id: Int, keyCode: UInt16, modifiers: UInt32, enabled: Bool)] = []
    private var shortcutsTable: [Int: ShortcutInfo] = [:]
    private var plistIdMap: [String: Int] = [:]
    private var loaded = false

    fileprivate struct ShortcutInfo {
        let id: Int
        let name: String
        let category: String?
        let bundlePath: String?
    }

    public override init() {
        super.init()
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        buildPlistIdMap()
        loadSymbolicHotKeys()
        loadShortcutsTable()
    }

    // MARK: - Plist ID Map

    private func buildPlistIdMap() {
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let appleKeys = plist["AppleSymbolicHotKeys"] as? [String: Any] else { return }

        for (key, value) in appleKeys {
            guard let dict = value as? [String: Any],
                  let valueDict = dict["value"] as? [String: Any],
                  let params = valueDict["parameters"] as? [Int],
                  params.count >= 3,
                  let symbolicId = Int(key) else { continue }
            plistIdMap["\(params[1])-\(params[2])"] = symbolicId
        }
    }

    // MARK: - Symbolic Hot Keys (Carbon)

    private func loadSymbolicHotKeys() {
        var hotKeysRef: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&hotKeysRef)
        guard status == noErr, let hotKeys = hotKeysRef?.takeRetainedValue() else { return }

        let count = CFArrayGetCount(hotKeys)
        for i in 0..<count {
            guard let dict = CFArrayGetValueAtIndex(hotKeys, i) else { continue }
            let cfDict = unsafeBitCast(dict, to: CFDictionary.self)

            guard let dictSwift = cfDict as NSDictionary as? [String: Any] else { continue }

            let kc = (dictSwift["kHISymbolicHotKeyCode"] as? NSNumber)?.int32Value ?? 0
            let mk = (dictSwift["kHISymbolicHotKeyModifiers"] as? NSNumber)?.int32Value ?? 0
            let en = (dictSwift["kHISymbolicHotKeyEnabled"] as? NSNumber)?.boolValue ?? false

            let symbolicId = plistIdMap["\(kc)-\(mk)"] ?? Int(i)
            symbolicHotKeys.append((id: symbolicId, keyCode: UInt16(kc), modifiers: UInt32(mk), enabled: en))
        }
    }

    // MARK: - Shortcuts Table (XML)

    private func loadShortcutsTable() {
        let paths = [
            "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources/en.lproj/DefaultShortcutsTable.xml",
            "/System/Library/PreferencePanes/Keyboard.prefPane/Contents/Resources/en.lproj/DefaultShortcutsTable.xml"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path),
               let data = FileManager.default.contents(atPath: path) {
                let parser = XMLParser(data: data)
                let delegate = ShortcutsTableParser()
                parser.delegate = delegate
                if parser.parse() {
                    shortcutsTable = delegate.shortcuts
                    return
                }
            }
        }
    }

    // MARK: - ShortcutResolver

    public func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        completion: @escaping (ShortcutOwnerResult?) -> Void
    ) {
        ensureLoaded()

        let targetCarbonMods = KeyCodeMap.modifiersToCarbon(modifiers)

        for entry in symbolicHotKeys where entry.enabled {
            if entry.keyCode == keyCode && entry.modifiers == targetCarbonMods {
                if let info = shortcutsTable[entry.id] {
                    completion(makeResult(from: info))
                    return
                }
                completion(makeResultForId(entry.id))
                return
            }
        }

        if let plistResult = checkSymbolicHotKeysPlist(keyCode: keyCode, rawModifiers: Int(targetCarbonMods)) {
            completion(plistResult)
            return
        }

        completion(nil)
    }

    // MARK: - Plist Lookup

    private func checkSymbolicHotKeysPlist(keyCode: UInt16, rawModifiers: Int) -> ShortcutOwnerResult? {
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let appleKeys = plist["AppleSymbolicHotKeys"] as? [String: Any] else {
            return nil
        }

        for (key, value) in appleKeys {
            guard let dict = value as? [String: Any],
                  let enabled = dict["enabled"] as? Bool, enabled,
                  let valueDict = dict["value"] as? [String: Any],
                  let params = valueDict["parameters"] as? [Int] else { continue }

            if params.count >= 3 && params[1] == Int(keyCode) && params[2] == rawModifiers {
                let symbolicId = Int(key) ?? -1
                if let info = shortcutsTable[symbolicId] {
                    return makeResult(from: info)
                }
                return makeResultForId(symbolicId)
            }
        }

        return nil
    }

    private func makeResult(from info: ShortcutInfo) -> ShortcutOwnerResult {
        ShortcutOwnerResult(
            bundleIdentifier: bundleIdFromPath(info.bundlePath) ?? "com.apple.systempreferences",
            appName: info.name,
            shortcutTitle: info.name,
            shortcutDescription: info.category,
            category: .system,
            isSystemShortcut: true
        )
    }

    private func makeResultForId(_ id: Int) -> ShortcutOwnerResult {
        if let info = shortcutsTable[id] {
            return makeResult(from: info)
        }
        let name = knownSystemShortcutName(id: id) ?? "System Shortcut"
        return ShortcutOwnerResult(
            bundleIdentifier: "com.apple.systempreferences",
            appName: "System Settings",
            shortcutTitle: name,
            shortcutDescription: nil,
            category: .system,
            isSystemShortcut: true
        )
    }

    // MARK: - Helpers

    private func bundleIdFromPath(_ path: String?) -> String? {
        guard let path = path else { return nil }
        let infoPath = path + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: infoPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    // MARK: - Public Query Helpers

    @objc public func isSystemShortcut(keyCode: UInt16, rawModifiers: Int) -> Bool {
        ensureLoaded()
        let carbonMods = UInt32(rawModifiers)
        for entry in symbolicHotKeys where entry.enabled {
            if entry.keyCode == keyCode && entry.modifiers == carbonMods {
                return true
            }
        }
        return checkSymbolicHotKeysPlist(keyCode: keyCode, rawModifiers: rawModifiers) != nil
    }

    @objc public func systemShortcutTitle(keyCode: UInt16, rawModifiers: Int) -> String? {
        ensureLoaded()
        let carbonMods = UInt32(rawModifiers)
        for entry in symbolicHotKeys where entry.enabled {
            if entry.keyCode == keyCode && entry.modifiers == carbonMods {
                if let name = shortcutsTable[entry.id]?.name ?? knownSystemShortcutName(id: entry.id) {
                    return name
                }
            }
        }
        return checkSymbolicHotKeysPlist(keyCode: keyCode, rawModifiers: rawModifiers)?.shortcutTitle
    }

    private func knownSystemShortcutName(id: Int) -> String? {
        let names: [Int: String] = [
            2: "Turn Dock Hiding On/Off",
            3: "Mission Control",
            4: "Application Windows",
            5: "Show All Windows",
            6: "Show Dashboard",
            7: "Display Zoom",
            8: "Spotlight",
            9: "Launchpad",
            10: "Show Help",
            11: "Decrease Display Brightness",
            12: "Increase Display Brightness",
            13: "Mission Control",
            14: "Expose",
            15: "Show Launchpad",
            16: "Dictation",
            17: "Do Not Disturb",
            18: "Media",
            19: "Show Desktop",
            20: "Mute",
            21: "Volume Down",
            22: "Volume Up",
            23: "Caps Lock",
            24: "Show Notification Center",
            25: "Keyboard Navigation",
            26: "Zoom",
            27: "VoiceOver",
            28: "Change Voice",
            29: "Siri",
            30: "Dictation",
            31: "Do Not Disturb",
            32: "Lock Screen",
            33: "Picture in Picture",
            34: "Reduce Motion",
            35: "Invert Colors",
            36: "Color Filters",
            37: "Zoom",
            38: "Switch Control",
            39: "Sticky Keys",
            40: "Slow Keys",
            41: "Mouse Keys",
            42: "Head Pointer",
            43: "Contrast",
            44: "Voice Control",
            45: "Control Center",
            46: "Lock Screen",
            47: "Notification Center",
            48: "Focus",
            49: "Screen Sharing",
            50: "Universal Access",
            51: "Accessibility",
            52: "Dock",
            53: "Window Management",
            54: "Spotlight",
            55: "Launchpad",
            56: "Siri",
            57: "Touch ID",
            58: "Apple Pay",
            59: "Quick Note",
            60: "Translate",
            61: "Screenshot",
            62: "Screen Recording",
            63: "Show Desktop",
            64: "Mission Control",
            65: "App Windows",
            66: "Show All Windows",
        ]
        return names[id]
    }
}

// MARK: - XML Parser

private class ShortcutsTableParser: NSObject, XMLParserDelegate {
    fileprivate var shortcuts: [Int: SystemShortcutResolver.ShortcutInfo] = [:]
    private var currentElement: [String: Any] = [:]
    private var currentKey = ""
    private var currentText = ""
    private var inDict = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = [:]
        currentKey = elementName
        currentText = ""
        if elementName == "dict" {
            inDict = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "key" {
            currentKey = text
        } else if elementName == "integer" {
            currentElement[currentKey] = Int(text) ?? 0
        } else if elementName == "string" {
            currentElement[currentKey] = text
        } else if elementName == "dict" && inDict {
            if let name = currentElement["name"] as? String,
               let id = currentElement["sybmolichotkey"] as? Int {
                shortcuts[id] = SystemShortcutResolver.ShortcutInfo(
                    id: id,
                    name: name.replacingOccurrences(of: "DO_NOT_LOCALIZE: ", with: ""),
                    category: currentElement["identifier"] as? String,
                    bundlePath: currentElement["icon-bundle-path"] as? String
                )
            }
            inDict = false
        }
    }
}
