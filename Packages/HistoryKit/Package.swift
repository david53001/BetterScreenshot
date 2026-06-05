// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HistoryKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HistoryKit", targets: ["HistoryKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "HistoryKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/HistoryKit HistoryKitTests
        .executableTarget(
            name: "HistoryKitTests",
            dependencies: ["HistoryKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/HistoryKitTests"
        ),
    ]
)
