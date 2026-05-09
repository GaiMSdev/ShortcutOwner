import Foundation
import AppKit
import CoreGraphics

/// Attempts to detect which app intercepts a given shortcut by installing a CGEventTap
/// and waiting for the next real keypress that matches.
///
/// **Current limitations (not production-ready):**
/// - Requires Input Monitoring permission from the user — most sandboxed apps won't get this.
/// - Passive listen-only tap: sees the event *after* all apps process it, not which app consumed it.
///   There is no public API to identify which app intercepted/suppressed an event.
/// - 3-second timeout: fires `nil` if the user doesn't press the shortcut within that window.
/// - `getTargetApp` returns `frontmostApplication`, which is the *focused* app, not necessarily
///   the one that registered the hotkey (hotkeys from background apps aren't visible here).
///
/// This resolver is included as a placeholder for future investigation. Until the limitations
/// above are addressed, it will typically return `nil` or an incorrect app. The system and
/// app resolvers (`SystemShortcutResolver`, `AppShortcutResolver`) are the reliable path.
@objc public class CGEventTapResolver: NSObject, ShortcutResolver {
    @objc public var requiresInputMonitoringPermission: Bool { true }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingResolve: ((ShortcutOwnerResult?) -> Void)?
    private var pendingKeyCode: UInt16 = 0
    private var pendingModifiers: NSEvent.ModifierFlags = []

    public override init() {
        super.init()
    }

    deinit {
        stopTapping()
    }

    @objc public var hasPermission: Bool {
        return CGPreflightListenEventAccess()
    }

    @objc public func requestPermission() {
        _ = CGRequestListenEventAccess()
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

        pendingResolve = completion
        pendingKeyCode = keyCode
        pendingModifiers = modifiers

        startTapping()
    }

    private func startTapping() {
        guard tap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo -> Unmanaged<CGEvent>? in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let resolver = Unmanaged<CGEventTapResolver>.fromOpaque(userInfo).takeUnretainedValue()
            return resolver.handleTapEvent(type: type, event: event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: info
        ) else {
            pendingResolve?(nil)
            pendingResolve = nil
            return
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        CGEvent.tapEnable(tap: newTap, enable: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            if self.pendingResolve != nil {
                self.stopTapping()
                self.pendingResolve?(nil)
                self.pendingResolve = nil
            }
        }
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let targetMods = pendingModifiers
        let targetKC = pendingKeyCode

        let flagsMatch = checkModifiersMatch(flags: flags, target: targetMods)

        if keyCode == targetKC && flagsMatch {
            let targetApp = getTargetApp(for: event)

            stopTapping()
            let result = pendingResolve
            pendingResolve = nil

            result?(ShortcutOwnerResult(
                bundleIdentifier: targetApp?.bundleIdentifier ?? "com.apple.dock",
                appName: targetApp?.localizedName ?? "System",
                shortcutTitle: nil,
                shortcutDescription: "Active shortcut detected via CGEventTap",
                category: .accessibility,
                isSystemShortcut: false
            ))

            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func checkModifiersMatch(flags: CGEventFlags, target: NSEvent.ModifierFlags) -> Bool {
        let cmdMatch = target.contains(.command) ? flags.contains(.maskCommand) : !flags.contains(.maskCommand)
        let shiftMatch = target.contains(.shift) ? flags.contains(.maskShift) : !flags.contains(.maskShift)
        let optMatch = target.contains(.option) ? flags.contains(.maskAlternate) : !flags.contains(.maskAlternate)
        let ctrlMatch = target.contains(.control) ? flags.contains(.maskControl) : !flags.contains(.maskControl)
        return cmdMatch && shiftMatch && optMatch && ctrlMatch
    }

    private func getTargetApp(for event: CGEvent) -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }

    private func stopTapping() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        self.tap = nil
        self.runLoopSource = nil
    }
}
