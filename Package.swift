// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tiley",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tiley", targets: ["Tiley"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK.git", from: "2.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tiley",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            resources: [
                .copy("menu-icon.pdf"),
                .copy("Images")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "TileyTests",
            dependencies: ["Tiley"]
        )
    ]
)
