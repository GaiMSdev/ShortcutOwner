// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShortcutOwner",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ShortcutOwner",
            type: .dynamic,
            targets: ["ShortcutOwner"]
        )
    ],
    targets: [
        .target(
            name: "ShortcutOwner",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .testTarget(
            name: "ShortcutOwnerTests",
            dependencies: ["ShortcutOwner"],
            path: "Tests/ShortcutOwnerTests"
        )
    ]
)
