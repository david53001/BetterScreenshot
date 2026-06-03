// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "CaptureKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/CaptureKit CaptureKitTests
        .executableTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/CaptureKitTests"
        ),
    ]
)
