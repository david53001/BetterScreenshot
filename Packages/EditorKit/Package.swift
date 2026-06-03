// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EditorKit", targets: ["EditorKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "EditorKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/EditorKit EditorKitTests
        .executableTarget(
            name: "EditorKitTests",
            dependencies: ["EditorKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/EditorKitTests"
        ),
    ]
)
