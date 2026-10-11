// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTaskCleaner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MacTaskCleanerCore",
            targets: ["MacTaskCleanerCore"]
        ),
        .executable(
            name: "MacTaskCleanerTestsRunner",
            targets: ["MacTaskCleanerTestsRunner"]
        ),
        .executable(
            name: "DummyTestTarget",
            targets: ["DummyTestTarget"]
        ),
        .executable(
            name: "MacTaskCleanerIntegrationTests",
            targets: ["MacTaskCleanerIntegrationTests"]
        )
    ],
    targets: [
        .target(
            name: "MacTaskCleanerCore",
            dependencies: []
        ),
        .executableTarget(
            name: "MacTaskCleanerTestsRunner",
            dependencies: ["MacTaskCleanerCore"]
        ),
        .executableTarget(
            name: "DummyTestTarget",
            dependencies: []
        ),
        .executableTarget(
            name: "MacTaskCleanerIntegrationTests",
            dependencies: ["MacTaskCleanerCore"]
        )
    ]
)
