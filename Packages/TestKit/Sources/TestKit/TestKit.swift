import Foundation

/// Collects assertion failures for a single test case.
public final class TestContext {
    public private(set) var failures: [String] = []
    public init() {}

    public func fail(_ message: String, file: StaticString = #file, line: UInt = #line) {
        let f = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
        failures.append("\(f):\(line): \(message)")
    }

    public func equal<T: Equatable>(_ a: T, _ b: T, _ msg: String = "",
                                    file: StaticString = #file, line: UInt = #line) {
        if a != b { fail("expected \(a) == \(b)\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
    }

    public func isNil<T>(_ a: T?, _ msg: String = "",
                         file: StaticString = #file, line: UInt = #line) {
        if a != nil { fail("expected nil, got \(String(describing: a!))\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
    }

    public func notNil<T>(_ a: T?, _ msg: String = "",
                          file: StaticString = #file, line: UInt = #line) {
        if a == nil { fail("expected non-nil\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
    }

    /// Returns the wrapped value, recording a failure (and returning nil) if absent.
    @discardableResult
    public func unwrap<T>(_ a: T?, _ msg: String = "",
                          file: StaticString = #file, line: UInt = #line) -> T? {
        if a == nil { fail("expected non-nil\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
        return a
    }

    public func isTrue(_ c: Bool, _ msg: String = "",
                       file: StaticString = #file, line: UInt = #line) {
        if !c { fail("expected true\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
    }

    public func isFalse(_ c: Bool, _ msg: String = "",
                        file: StaticString = #file, line: UInt = #line) {
        if c { fail("expected false\(msg.isEmpty ? "" : " — \(msg)")", file: file, line: line) }
    }

    public func approxEqual(_ a: Double, _ b: Double, tol: Double = 1e-9,
                            file: StaticString = #file, line: UInt = #line) {
        if abs(a - b) > tol { fail("expected \(a) ≈ \(b) (tol \(tol))", file: file, line: line) }
    }
}

/// A named test: the body records failures on the provided context.
public struct TestCase {
    public let name: String
    public let body: (TestContext) -> Void
    public init(_ name: String, _ body: @escaping (TestContext) -> Void) {
        self.name = name
        self.body = body
    }
}

/// Runs all cases, prints a summary, and exits non-zero if any failed.
public func runTests(_ suite: String, _ cases: [TestCase]) -> Never {
    var totalFailures = 0
    var passed = 0
    print("▶ \(suite): running \(cases.count) test(s)…")
    for c in cases {
        let ctx = TestContext()
        c.body(ctx)
        if ctx.failures.isEmpty {
            passed += 1
            print("  ✓ \(c.name)")
        } else {
            totalFailures += ctx.failures.count
            print("  ✗ \(c.name)")
            for f in ctx.failures { print("      \(f)") }
        }
    }
    let status = totalFailures == 0 ? "PASS" : "FAIL"
    print("\(status) — \(suite): \(passed)/\(cases.count) test(s) passed, \(totalFailures) failure(s)")
    exit(totalFailures == 0 ? 0 : 1)
}
