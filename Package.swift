import PackageDescription

let package = Package(
    name: "SwiftBot",
    targets: [
        Target(name: "SwiftBot", dependencies: ["Shared"]),
        Target(name: "SwiftBotDistributed", dependencies: ["Shared"])
    ],
    dependencies: [
        .Package(url: "https://github.com/nuclearace/SwiftDiscord", majorVersion: 2),
        .Package(url: "https://github.com/nuclearace/ImageBrutalizer", majorVersion: 1),
        .Package(url: "https://github.com/nuclearace/SwiftRateLimiter", majorVersion: 1)
    ],
    exclude: ["Shared"]
)
