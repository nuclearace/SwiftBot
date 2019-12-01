// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "SwiftBot",
    products: [
        .executable(name: "SwiftBot", targets: ["SwiftBot"]),
        .executable(name: "SwiftShard", targets: ["SwiftShard"])
    ],
    dependencies: [
        .package(url: "https://github.com/nuclearace/SwiftDiscord", .branch("vapor3")),
        .package(url: "https://github.com/nuclearace/SwiftRateLimiter", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMinor(from: "1.2.0")),
        .package(url: "https://github.com/nuclearace/CleverSwift", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/vapor/http", .revision("3e49ea0b7c16ee0e0985babff9659d467d4f59fd"))
//        .package(url: "https://github.com/vapor/websocket", .upToNextMinor(from: "1.0.0")),
    ],
    targets: [
        .target(name: "SwiftShard", dependencies: ["SwiftDiscord", "Shared", "CryptoSwift", "Cleverbot",
                                                   "SwiftRateLimiter", "HTTPKit"]),
        .target(name: "SwiftBot", dependencies: ["SwiftDiscord", "Shared", "CryptoSwift", "SwiftRateLimiter",
                                                 "HTTPKit"]),
        .target(name: "Shared", dependencies: ["SwiftDiscord"])
    ]
)
