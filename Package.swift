import PackageDescription

let package = Package(
    name: "SwiftBot",
    dependencies: [
        .Package(url: "https://github.com/nuclearace/SwiftDiscord", majorVersion: 1),
        .Package(url: "https://github.com/nuclearace/ImageBrutalizer", majorVersion: 1),
        .Package(url: "https://github.com/nuclearace/SwiftRateLimiter", majorVersion: 1)
    ]
)
