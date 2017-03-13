import PackageDescription

let package = Package(
    name: "SwiftBot",
    targets: [
        Target(name: "SwiftShard", dependencies: ["Shared"]),
        Target(name: "SwiftBot", dependencies: ["Shared"])
    ],
    dependencies: [
        .Package(url: "https://github.com/nuclearace/SwiftDiscord", majorVersion: 3),
        .Package(url: "https://github.com/nuclearace/ImageBrutalizer", majorVersion: 1),
        .Package(url: "https://github.com/nuclearace/SwiftRateLimiter", majorVersion: 1),
        .Package(url: "https://github.com/krzyzanowskim/CryptoSwift", majorVersion: 0, minor: 6),
        .Package(url: "https://github.com/nuclearace/CleverSwift", majorVersion: 0, minor: 1)
    ],
    exclude: ["Shared"]
)
