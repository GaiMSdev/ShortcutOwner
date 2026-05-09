import XCTest
@testable import ShortcutOwner

final class ShortcutOwnerTests: XCTestCase {
    func testKeyCodeMap() {
        XCTAssertEqual(ShortcutOwner.keyName(for: 35), "P")
        XCTAssertEqual(ShortcutOwner.keyName(for: 36), "Return")
        XCTAssertEqual(ShortcutOwner.keyName(for: 49), "Space")
        XCTAssertEqual(ShortcutOwner.keyName(for: 53), "Escape")
        XCTAssertEqual(ShortcutOwner.keyName(for: 999), "Key999")
    }

    func testShortcutString() {
        let str = ShortcutOwner.shortcutString(
            keyCode: 35,
            modifiers: [.command, .shift]
        )
        XCTAssertEqual(str, "⇧⌘P")
    }

    func testSystemShortcutResolverKeyCodeCheck() {
        let resolver = SystemShortcutResolver()
        // Mission Control is typically Cmd+Control+Up on many systems
        // We just verify it doesn't crash
        let result = resolver.isSystemShortcut(keyCode: 126, rawModifiers: 768)
        XCTAssertNotNil(result)
    }

    func testSystemShortcutTitleCheck() {
        let resolver = SystemShortcutResolver()
        let title = resolver.systemShortcutTitle(keyCode: 126, rawModifiers: 768)
        print("Title: \(String(describing: title))")
    }

    func testLiveShortcutResolution() {
        let resolver = SystemShortcutResolver()
        let cases: [(UInt16, UInt32, String)] = [
            (35,  0x100 | 0x200, "⌘⇧P  (OnePlayer default)"),
            (49,  0x100,         "⌘Space (Spotlight)"),
            (99,  0,             "F3    (Mission Control)"),
            (103, 0,             "F11   (Show Desktop)"),
            (12,  0x100 | 0x200, "⌘⇧Q  (logout? screenshot?)"),
            (20,  0x100 | 0x200, "⌘⇧3  (screenshot)"),
        ]
        print("\n--- Live ShortcutOwner test on this Mac ---")
        for (kc, mods, label) in cases {
            let taken = resolver.isSystemShortcut(keyCode: kc, rawModifiers: Int(mods))
            let name  = resolver.systemShortcutTitle(keyCode: kc, rawModifiers: Int(mods)) ?? "—"
            print("\(label): taken=\(taken)  name=\(name)")
        }
        print("-------------------------------------------\n")
    }
}
