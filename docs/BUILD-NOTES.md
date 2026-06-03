# Build & Test Notes — environment deviations from the plans

The three implementation plans assume **XcodeGen + xcodebuild** and **XCTest +
`swift test`**. This machine has only the **Command Line Tools** (no full
Xcode), so neither is available. The code in the plans is implemented
faithfully; only the *build/test tooling* is adapted. Two deviations:

## 1. Build system: Swift Package Manager instead of XcodeGen/xcodebuild

- `xcodebuild` requires full Xcode (`xcode-select -p` points at
  `CommandLineTools`); installing Xcode is not possible here.
- The whole project builds with **SwiftPM**:
  - Library modules stay exactly where the plans put them
    (`Packages/CaptureKit`, `Packages/OverlayKit`, `Packages/EditorKit`),
    each its own `Package.swift`.
  - A **root `Package.swift`** adds the app as an `.executableTarget`
    (`name: "BetterScreenshot", path: "App"`) depending on the library
    products. Build: `swift build`.
  - The runnable `.app` bundle is assembled by **`scripts/build-app.sh`**
    (copies the SwiftPM-built binary + `App/Info.plist` + `AppIcon.icns`,
    then ad-hoc `codesign`). This replaces every
    `xcodegen generate && xcodebuild …` step in the plans.
- All `swift build` / file paths in the plans remain valid as written.

## 2. Tests: TestKit micro-harness instead of XCTest

- XCTest is not present under CLT (no `XCTest.framework` for macOS, no
  `xctest` runner). swift-testing compiles but does not run reliably via
  `swift test` here.
- Each package's test suite is a small **executable target** that depends on
  **`Packages/TestKit`** (a ~90-line assertion harness) and is run with
  `swift run`. Test directories and file names match the plans
  (`Tests/CaptureKitTests/…`); only the syntax changes:
  - `XCTestCase` methods → entries in a `let xxxTests: [TestCase]` array.
  - `XCTAssertEqual(a, b)` → `t.equal(a, b)`; `XCTAssertNil` → `t.isNil`;
    `XCTUnwrap` → `t.unwrap`; `XCTAssertTrue/False` → `t.isTrue/isFalse`.
  - Each target has a `main.swift` that calls
    `runTests("Suite", arrayA + arrayB + …)`.
- Run a suite: `swift run --package-path Packages/CaptureKit CaptureKitTests`
  (exit code 0 = all passed, non-zero = failures, with per-test output).

The assertions, expected values, and the code under test are identical to the
plans.
