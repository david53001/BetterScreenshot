# TestKit — the local test harness

A minimal, dependency-free test harness used **in place of XCTest**. XCTest is unavailable under the
macOS Command Line Tools (no `XCTest.framework` / `xctest` runner), so each package's test suite is a
plain **executable** target (`Tests/<Name>Tests/`) that depends on TestKit and is run with
`swift run`.

- This package ships only the harness (`Sources/TestKit/TestKit.swift`); it has no tests of its own.
- Every other package depends on it via `.package(path: "../TestKit")`.

## Run the suites
- All packages: `scripts/test.sh`.
- One package: `swift run --package-path Packages/<Name> <Name>Tests`.
