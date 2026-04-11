// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BananaPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BananaPlayer", targets: ["BananaPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "BananaPlayer"
        )
    ],
    swiftLanguageModes: [.v6]
)
