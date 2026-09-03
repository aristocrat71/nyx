// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nyx",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nyx",
            resources: [.copy("Resources/Fonts"), .copy("Resources/owl.png")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NyxTests",
            dependencies: ["Nyx"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
