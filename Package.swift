// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "SwiftBot",
    products: [
        .executable(name: "SwiftBot", targets: ["SwiftBot"]),
        .executable(name: "SwiftShard", targets: ["SwiftShard"])
    ],
    dependencies: [
        .package(url: "https://github.com/nuclearace/SwiftDiscord", .upToNextMajor(from: "8.0.0")),
        .package(url: "https://github.com/nuclearace/SwiftRateLimiter", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMinor(from: "0.7.2")),
        .package(url: "https://github.com/nuclearace/CleverSwift", .upToNextMinor(from: "0.1.4")),
//        .package(url: "https://github.com/vapor/websocket", .upToNextMinor(from: "1.0.0")),
    ],
    targets: [
        .target(name: "SwiftShard", dependencies: ["SwiftDiscord", "Shared", "CryptoSwift", "Cleverbot",
                                                   "SwiftRateLimiter"]),
        .target(name: "SwiftBot", dependencies: ["SwiftDiscord", "Shared", "CryptoSwift", "SwiftRateLimiter"]),
        .target(name: "Shared", dependencies: ["SwiftDiscord"])
    ]
)
