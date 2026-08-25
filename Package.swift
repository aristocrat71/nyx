// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nyx",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nyx",
            resources: [.copy("Resources/Fonts")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
