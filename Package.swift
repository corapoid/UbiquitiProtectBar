// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProtectBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/mpvkit/MPVKit", from: "0.41.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ProtectBar",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "ProtectBar",
            exclude: ["Info.plist", "ProtectBar.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ProtectBarTests",
            dependencies: [],
            path: "Tests/ProtectBarTests"
        )
    ]
)
