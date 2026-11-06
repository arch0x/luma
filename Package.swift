// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Luma", targets: ["Luma"])],
    targets: [
        .target(name: "ReaderCore"),
        .executableTarget(
            name: "Luma",
            dependencies: ["ReaderCore"],
            resources: [.copy("Resources/Samples"), .copy("Resources/Markdown"), .copy("Resources/Brand")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "LumaTests", dependencies: ["Luma"])
    ]
)
