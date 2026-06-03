// swift-tools-version:5.9
import PackageDescription

// Minimal, dependency-free test harness used in place of XCTest.
// XCTest is unavailable under the Command Line Tools (no XCTest.framework for
// macOS, no `xctest` runner), so package test suites are built as plain
// executable targets that depend on TestKit and are run with `swift run`.
let package = Package(
    name: "TestKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TestKit", targets: ["TestKit"])],
    targets: [.target(name: "TestKit")]
)
