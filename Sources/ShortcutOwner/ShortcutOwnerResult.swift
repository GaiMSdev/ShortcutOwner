import Foundation
import AppKit

@objc public class ShortcutOwnerResult: NSObject {
    @objc public let bundleIdentifier: String
    @objc public let appName: String
    @objc public let shortcutTitle: String?
    @objc public let shortcutDescription: String?
    @objc public let category: ShortcutCategory
    @objc public let isSystemShortcut: Bool

    @objc public init(
        bundleIdentifier: String,
        appName: String,
        shortcutTitle: String?,
        shortcutDescription: String?,
        category: ShortcutCategory,
        isSystemShortcut: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.shortcutTitle = shortcutTitle
        self.shortcutDescription = shortcutDescription
        self.category = category
        self.isSystemShortcut = isSystemShortcut
        super.init()
    }
}

@objc public enum ShortcutCategory: Int {
    case unknown = 0
    case system = 1
    case app = 2
    case accessibility = 3
}

@objc public protocol ShortcutResolver {
    func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        completion: @escaping (ShortcutOwnerResult?) -> Void
    )
    @objc optional func supportsAccessibility() -> Bool
    @objc optional var requiresAccessibilityPermission: Bool { get }
    @objc optional var requiresInputMonitoringPermission: Bool { get }
}
