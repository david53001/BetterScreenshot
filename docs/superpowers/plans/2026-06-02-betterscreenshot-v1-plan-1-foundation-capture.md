# BetterScreenshot v1 — Plan 1: Foundation & Capture Core

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A non-sandboxed macOS menu-bar app that, via global hotkeys or menu, captures an area / window / fullscreen screenshot and both copies it to the clipboard and saves it as a PNG to a configurable folder, with graceful Screen-Recording permission handling.

**Architecture:** A menu-bar agent app (`LSUIElement`) depends on two local Swift packages: `CaptureKit` (ScreenCaptureKit wrapper + pure geometry/crop/encode logic) and `OverlayKit` (the area-selection overlay window). App-level code in `App/` wires hotkeys → permission check → capture → file output. Pure logic is TDD'd with `swift test`; system/UI behavior is verified manually against a scripted checklist.

**Tech Stack:** Swift 5.9+, macOS 14 (Sonoma) deployment target, ScreenCaptureKit, Carbon `RegisterEventHotKey`, AppKit, SwiftUI (settings), XCTest, XcodeGen (project generation), `xcodebuild` (build/run).

**Reference docs:** `docs/superpowers/specs/2026-06-02-betterscreenshot-v1-design.md` (design) and `CLEANSHOT-X-FEATURE-SPEC.md` (target features).

**Out of scope for this plan (later plans):** the Quick Access thumbnail overlay (Plan 2), the annotation editor (Plan 3), recording, OCR, pin, scrolling, backgrounds, JPG/WebP options beyond a format toggle stub, history.

---

## Prerequisites (one-time, do before Task 1)

- macOS 14+ with Xcode 15+ installed (`xcode-select -p` should print a path).
- Install XcodeGen: `brew install xcodegen` (verify: `xcodegen --version`).
- Working directory is the repo root: `/Users/davidghermansteinberg/Desktop/Home/Code/BetterScreenshot`.
- This is not yet a git repo. Task 1 initializes it.

---

## File Structure (created across this plan)

```
BetterScreenshot/
├── project.yml                          # XcodeGen project definition
├── .gitignore
├── App/
│   ├── Info.plist                       # LSUIElement = true
│   ├── BetterScreenshot.entitlements    # non-sandboxed (no sandbox key)
│   ├── BetterScreenshotApp.swift        # @main entry, AppDelegate
│   ├── MenuBarController.swift          # NSStatusItem + menu
│   ├── CaptureCoordinator.swift         # orchestration (hotkey→capture→output)
│   ├── HotKeyManager.swift              # Carbon global hotkeys
│   ├── PermissionManager.swift          # screen-recording TCC flow
│   ├── SettingsStore.swift              # UserDefaults-backed settings
│   └── SettingsView.swift               # SwiftUI settings pane
├── Packages/
│   ├── CaptureKit/
│   │   ├── Package.swift
│   │   ├── Sources/CaptureKit/
│   │   │   ├── CaptureTarget.swift      # enum: area/window/fullscreen
│   │   │   ├── CaptureGeometry.swift    # PURE: global rect → pixel rect
│   │   │   ├── ImageCropper.swift       # PURE: crop CGImage
│   │   │   ├── ImageEncoder.swift       # PURE: CGImage → PNG/JPG Data
│   │   │   ├── FileNamer.swift          # PURE: timestamp filenames
│   │   │   └── CaptureService.swift     # ScreenCaptureKit calls (manual-tested)
│   │   └── Tests/CaptureKitTests/
│   │       ├── CaptureGeometryTests.swift
│   │       ├── ImageCropperTests.swift
│   │       ├── ImageEncoderTests.swift
│   │       └── FileNamerTests.swift
│   └── OverlayKit/
│       ├── Package.swift
│       └── Sources/OverlayKit/
│           ├── SelectionResult.swift     # PURE-ish value type
│           └── SelectionOverlayController.swift  # NSWindow (manual-tested)
└── docs/…                                # specs + this plan
```

---

## Task 1: Repo + toolchain scaffold

**Files:**
- Create: `.gitignore`, `project.yml`, `App/Info.plist`, `App/BetterScreenshot.entitlements`, `App/BetterScreenshotApp.swift`, `Packages/CaptureKit/Package.swift`, `Packages/CaptureKit/Sources/CaptureKit/CaptureKit.swift`, `Packages/OverlayKit/Package.swift`, `Packages/OverlayKit/Sources/OverlayKit/OverlayKit.swift`

- [ ] **Step 1: Initialize git**

Run:
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Code/BetterScreenshot
git init
```
Expected: `Initialized empty Git repository …`

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
/build/
/DerivedData/
*.xcodeproj
*.xcworkspace
.swiftpm/
xcuserdata/
```
(We generate the `.xcodeproj` with XcodeGen, so it stays out of git.)

- [ ] **Step 3: Write the two package manifests**

`Packages/CaptureKit/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    targets: [
        .target(name: "CaptureKit"),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
```

`Packages/OverlayKit/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OverlayKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OverlayKit", targets: ["OverlayKit"])],
    targets: [.target(name: "OverlayKit")]
)
```

- [ ] **Step 4: Add placeholder sources so packages compile**

`Packages/CaptureKit/Sources/CaptureKit/CaptureKit.swift`:
```swift
// Umbrella file. Concrete types live in their own files.
public enum CaptureKitInfo {
    public static let version = "0.1.0"
}
```

`Packages/OverlayKit/Sources/OverlayKit/OverlayKit.swift`:
```swift
public enum OverlayKitInfo {
    public static let version = "0.1.0"
}
```

- [ ] **Step 5: Verify packages build**

Run:
```bash
swift build --package-path Packages/CaptureKit
swift build --package-path Packages/OverlayKit
```
Expected: `Build complete!` for each.

- [ ] **Step 6: Write app Info.plist**

`App/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>BetterScreenshot</string>
    <key>CFBundleIdentifier</key><string>com.betterscreenshot.app</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```
Note: Screen Recording (ScreenCaptureKit) does NOT require a usage-description key; macOS manages that TCC grant itself. (Mic/camera keys come in Plan 2/recording phases.)

- [ ] **Step 7: Write entitlements (non-sandboxed)**

`App/BetterScreenshot.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Intentionally no com.apple.security.app-sandbox key: the app runs non-sandboxed. -->
</dict>
</plist>
```

- [ ] **Step 8: Write a minimal `@main` app that launches as a menu-bar agent**

`App/BetterScreenshotApp.swift`:
```swift
import SwiftUI

@main
struct BetterScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No window scene: this is a menu-bar agent. Settings window added later.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // belt-and-suspenders with LSUIElement
        NSLog("BetterScreenshot launched")
    }
}
```

- [ ] **Step 9: Write `project.yml`**

`project.yml`:
```yaml
name: BetterScreenshot
options:
  bundleIdPrefix: com.betterscreenshot
  deploymentTarget:
    macOS: "14.0"
packages:
  CaptureKit:
    path: Packages/CaptureKit
  OverlayKit:
    path: Packages/OverlayKit
targets:
  BetterScreenshot:
    type: application
    platform: macOS
    sources: [App]
    info:
      path: App/Info.plist
    entitlements:
      path: App/BetterScreenshot.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.betterscreenshot.app
        MARKETING_VERSION: "0.1.0"
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"      # ad-hoc signing
        SWIFT_VERSION: "5.9"
    dependencies:
      - package: CaptureKit
      - package: OverlayKit
```

- [ ] **Step 10: Generate and build the app**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Launch and confirm it runs as an agent**

Run:
```bash
open build/Build/Products/Debug/BetterScreenshot.app
```
Expected: no Dock icon, no window; `log show --last 1m --predicate 'eventMessage contains "BetterScreenshot launched"'` shows the launch line (or check Console.app). Quit with `killall BetterScreenshot`.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "chore: scaffold menu-bar app + CaptureKit/OverlayKit packages (XcodeGen)"
```

---

## Task 2: CaptureGeometry (PURE — global selection rect → pixel rect)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/CaptureGeometry.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureGeometryTests.swift`

Context: the selection overlay returns a rectangle in Cocoa global coordinates (origin bottom-left, points). A `CGImage` is top-left origin in pixels. This converts one to the other given the target display's frame and backing scale.

- [ ] **Step 1: Write the failing test**

`CaptureGeometryTests.swift`:
```swift
import XCTest
@testable import CaptureKit

final class CaptureGeometryTests: XCTestCase {
    func testConvertsGlobalRectToTopLeftPixelRect() {
        // Display: 1440x900 pt at scale 2 → 2880x1800 px, origin (0,0).
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Selection in Cocoa (bottom-left origin): x100 y100 w200 h150.
        let selection = CGRect(x: 100, y: 100, width: 200, height: 150)
        let px = CaptureGeometry.pixelRect(forGlobalRect: selection,
                                           inDisplayFrame: display, scale: 2)
        // x = (100-0)*2 = 200; top y = (900 - (100+150))*2 = 1300; w=400; h=300
        XCTAssertEqual(px, CGRect(x: 200, y: 1300, width: 400, height: 300))
    }

    func testHandlesNonZeroDisplayOrigin() {
        let display = CGRect(x: 1440, y: 0, width: 1920, height: 1080) // second display
        let selection = CGRect(x: 1540, y: 80, width: 100, height: 100)
        let px = CaptureGeometry.pixelRect(forGlobalRect: selection,
                                           inDisplayFrame: display, scale: 1)
        // x=(1540-1440)=100; top y=(1080-(80+100))=900; w=100; h=100
        XCTAssertEqual(px, CGRect(x: 100, y: 900, width: 100, height: 100))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureGeometryTests`
Expected: FAIL — `cannot find 'CaptureGeometry' in scope`.

- [ ] **Step 3: Write minimal implementation**

`CaptureGeometry.swift`:
```swift
import CoreGraphics

public enum CaptureGeometry {
    /// Convert a rect in Cocoa global coordinates (bottom-left origin, points)
    /// into a top-left-origin pixel rect relative to a captured display image.
    public static func pixelRect(forGlobalRect rect: CGRect,
                                 inDisplayFrame display: CGRect,
                                 scale: CGFloat) -> CGRect {
        let xLocal = (rect.minX - display.minX) * scale
        let yTopLocal = (display.maxY - rect.maxY) * scale
        return CGRect(x: xLocal, y: yTopLocal,
                      width: rect.width * scale, height: rect.height * scale)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureGeometryTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): CaptureGeometry global→pixel rect conversion"
```

---

## Task 3: ImageCropper (PURE — crop a CGImage to a pixel rect)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/ImageCropper.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/ImageCropperTests.swift`

- [ ] **Step 1: Write the failing test**

`ImageCropperTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import CaptureKit

final class ImageCropperTests: XCTestCase {
    /// Build a solid-color CGImage of given pixel size.
    private func makeImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testCropsToExactPixelRect() {
        let img = makeImage(width: 200, height: 100)
        let cropped = ImageCropper.crop(img, to: CGRect(x: 10, y: 20, width: 50, height: 30))
        XCTAssertEqual(cropped?.width, 50)
        XCTAssertEqual(cropped?.height, 30)
    }

    func testClampsRectToImageBounds() {
        let img = makeImage(width: 100, height: 100)
        // Rect partially outside → clamp to 100x100 area, here from (90,90) size 50→ clamps to 10x10
        let cropped = ImageCropper.crop(img, to: CGRect(x: 90, y: 90, width: 50, height: 50))
        XCTAssertEqual(cropped?.width, 10)
        XCTAssertEqual(cropped?.height, 10)
    }

    func testReturnsNilForZeroAreaRect() {
        let img = makeImage(width: 100, height: 100)
        XCTAssertNil(ImageCropper.crop(img, to: CGRect(x: 0, y: 0, width: 0, height: 0)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter ImageCropperTests`
Expected: FAIL — `cannot find 'ImageCropper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ImageCropper.swift`:
```swift
import CoreGraphics

public enum ImageCropper {
    /// Crop with integer pixel rounding, clamped to the image bounds.
    /// Returns nil if the resulting rect has zero area.
    public static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return image.cropping(to: clamped)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter ImageCropperTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): ImageCropper with bounds clamping"
```

---

## Task 4: ImageEncoder (PURE — CGImage → PNG/JPG Data)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/ImageEncoder.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/ImageEncoderTests.swift`

- [ ] **Step 1: Write the failing test**

`ImageEncoderTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import CaptureKit

final class ImageEncoderTests: XCTestCase {
    private func makeImage() -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return ctx.makeImage()!
    }

    func testEncodesPNGWithCorrectSignature() throws {
        let data = try XCTUnwrap(ImageEncoder.encode(makeImage(), as: .png))
        // PNG magic: 89 50 4E 47
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testEncodesJPEGWithCorrectSignature() throws {
        let data = try XCTUnwrap(ImageEncoder.encode(makeImage(), as: .jpg(quality: 0.8)))
        // JPEG magic: FF D8
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter ImageEncoderTests`
Expected: FAIL — `cannot find 'ImageEncoder' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ImageEncoder.swift`:
```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: Equatable {
    case png
    case jpg(quality: CGFloat)
}

public enum ImageEncoder {
    public static func encode(_ image: CGImage, as format: ImageFormat) -> Data? {
        let utType: UTType = {
            switch format { case .png: return .png; case .jpg: return .jpeg }
        }()
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, utType.identifier as CFString, 1, nil
        ) else { return nil }
        var options: [CFString: Any] = [:]
        if case let .jpg(quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter ImageEncoderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): ImageEncoder for PNG/JPG"
```

---

## Task 5: FileNamer (PURE — timestamped filenames)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/FileNamer.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/FileNamerTests.swift`

- [ ] **Step 1: Write the failing test**

`FileNamerTests.swift`:
```swift
import XCTest
@testable import CaptureKit

final class FileNamerTests: XCTestCase {
    func testProducesDeterministicNameForFixedDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2026, month: 6, day: 2,
                                   hour: 14, minute: 32, second: 10)
        let date = cal.date(from: comps)!
        let name = FileNamer.fileName(for: date, ext: "png",
                                      timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "Screenshot 2026-06-02 at 14.32.10.png")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter FileNamerTests`
Expected: FAIL — `cannot find 'FileNamer' in scope`.

- [ ] **Step 3: Write minimal implementation**

`FileNamer.swift`:
```swift
import Foundation

public enum FileNamer {
    public static func fileName(for date: Date, ext: String,
                                timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(f.string(from: date)).\(ext)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter FileNamerTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): FileNamer timestamped filenames"
```

---

## Task 6: CaptureTarget + CaptureService (ScreenCaptureKit — MANUAL verify)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/CaptureTarget.swift`, `Packages/CaptureKit/Sources/CaptureKit/CaptureService.swift`

Context: `SCScreenshotManager.captureImage` (macOS 14+) returns a `CGImage` directly. For an area capture we grab the full display, then crop with `CaptureGeometry` + `ImageCropper`. This file calls live system APIs and cannot be unit-tested — verify manually in Task 11.

- [ ] **Step 1: Define the capture target type**

`CaptureTarget.swift`:
```swift
import CoreGraphics

public enum CaptureTarget {
    /// Selection rect in Cocoa global coordinates (points), plus the display it lives on.
    case area(rect: CGRect, displayID: CGDirectDisplayID)
    case fullscreen(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID)
}
```

- [ ] **Step 2: Implement CaptureService**

`CaptureService.swift`:
```swift
import ScreenCaptureKit
import CoreGraphics

public enum CaptureError: Error {
    case noShareableContent
    case displayNotFound
    case windowNotFound
    case cropFailed
}

public struct CaptureService {
    public init() {}

    public func capture(_ target: CaptureTarget) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        switch target {
        case let .fullscreen(displayID):
            let (filter, config) = try displayFilter(displayID, content: content)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)

        case let .area(rect, displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.displayNotFound }
            let (filter, config) = try displayFilter(displayID, content: content)
            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            let scale = CGFloat(full.width) / CGFloat(display.width)
            let pixelRect = CaptureGeometry.pixelRect(
                forGlobalRect: rect, inDisplayFrame: display.frame, scale: scale)
            guard let cropped = ImageCropper.crop(full, to: pixelRect)
            else { throw CaptureError.cropFailed }
            return cropped

        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID })
            else { throw CaptureError.windowNotFound }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        }
    }

    private func displayFilter(_ displayID: CGDirectDisplayID,
                               content: SCShareableContent)
        throws -> (SCContentFilter, SCStreamConfiguration) {
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw CaptureError.displayNotFound }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * 2)   // capture at @2x; refined later
        config.height = Int(CGFloat(display.height) * 2)
        config.showsCursor = false
        return (filter, config)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build --package-path Packages/CaptureKit`
Expected: `Build complete!` (no unit test — exercised end-to-end in Task 11).

- [ ] **Step 4: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): CaptureService via SCScreenshotManager (area/window/fullscreen)"
```

---

## Task 7: PermissionManager (screen-recording TCC — MANUAL verify)

**Files:**
- Create: `App/PermissionManager.swift`

- [ ] **Step 1: Implement**

`App/PermissionManager.swift`:
```swift
import CoreGraphics
import AppKit

enum PermissionManager {
    /// True if screen-recording permission is already granted.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt (first call) — returns immediately.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Shown when permission is missing: explains and deep-links to System Settings.
    static func presentDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "BetterScreenshot needs Screen Recording access to capture your screen. Enable it in System Settings → Privacy & Security → Screen Recording, then relaunch."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles (will be exercised in Task 11)**

This file is referenced by the app target; it compiles when the app builds in Task 11. No standalone build step here.

- [ ] **Step 3: Commit**

```bash
git add App/PermissionManager.swift
git commit -m "feat(app): screen-recording permission manager"
```

---

## Task 8: HotKeyManager (Carbon global hotkeys)

**Files:**
- Create: `App/HotKeyManager.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/KeyCodeTests.swift` (we put the PURE mapping in CaptureKit so it's testable with `swift test`)
- Create: `Packages/CaptureKit/Sources/CaptureKit/KeyCombo.swift`

Context: `RegisterEventHotKey` needs a Carbon virtual key code + Carbon modifier mask. The mapping is pure and testable; the registration itself (Carbon event handler) is manual-verified.

- [ ] **Step 1: Write the failing test for the pure mapping**

`KeyCodeTests.swift`:
```swift
import XCTest
@testable import CaptureKit

final class KeyCodeTests: XCTestCase {
    func testDigitKeyCodes() {
        XCTAssertEqual(KeyCombo.carbonKeyCode(for: "4"), 21)
        XCTAssertEqual(KeyCombo.carbonKeyCode(for: "5"), 23)
        XCTAssertEqual(KeyCombo.carbonKeyCode(for: "6"), 22)
    }

    func testCarbonModifierMask() {
        // cmd+shift
        let mask = KeyCombo.carbonModifiers(command: true, shift: true,
                                            option: false, control: false)
        // cmdKey = 0x0100, shiftKey = 0x0200 → 0x0300 = 768
        XCTAssertEqual(mask, 768)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter KeyCodeTests`
Expected: FAIL — `cannot find 'KeyCombo' in scope`.

- [ ] **Step 3: Implement the pure mapping**

`Packages/CaptureKit/Sources/CaptureKit/KeyCombo.swift`:
```swift
import Foundation

public enum KeyCombo {
    /// Carbon virtual key codes for the small set of keys we bind by default.
    public static func carbonKeyCode(for key: Character) -> UInt32? {
        switch key {
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        default: return nil
        }
    }

    /// Carbon modifier flags (cmdKey=0x0100, shiftKey=0x0200, optionKey=0x0800, controlKey=0x1000).
    public static func carbonModifiers(command: Bool, shift: Bool,
                                       option: Bool, control: Bool) -> UInt32 {
        var m: UInt32 = 0
        if command { m |= 0x0100 }
        if shift   { m |= 0x0200 }
        if option  { m |= 0x0800 }
        if control { m |= 0x1000 }
        return m
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter KeyCodeTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Implement the Carbon registration wrapper (manual-verified)**

`App/HotKeyManager.swift`:
```swift
import Carbon
import CaptureKit

final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() { installHandler() }

    /// Register a combo; returns false if registration fails (e.g. already taken).
    @discardableResult
    func register(key: Character, command: Bool, shift: Bool,
                  option: Bool, control: Bool, action: @escaping () -> Void) -> Bool {
        guard let code = KeyCombo.carbonKeyCode(for: key) else { return false }
        let mods = KeyCombo.carbonModifiers(command: command, shift: shift,
                                            option: option, control: control)
        let id = EventHotKeyID(signature: OSType(0x42535343 /* 'BSSC' */), id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return false }
        actions[nextID] = action
        hotKeyRefs.append(ref)
        nextID += 1
        return true
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mgr.actions[hkID.id]?()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Packages/CaptureKit App/HotKeyManager.swift
git commit -m "feat(app): Carbon global hotkeys + testable keycode mapping"
```

---

## Task 9: SettingsStore (UserDefaults-backed)

**Files:**
- Create: `App/SettingsStore.swift`
- Test: `App/SettingsStoreTests` are not run via swift test (app target). Instead put the PURE logic in CaptureKit so it is testable: create `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift` + `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`.

Context: keep the encode/decode + defaults logic pure and testable in CaptureKit; the app's `SettingsStore` is a thin `UserDefaults` adapter around it.

- [ ] **Step 1: Write the failing test**

`Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`:
```swift
import XCTest
@testable import CaptureKit

final class CaptureSettingsTests: XCTestCase {
    func testDefaults() {
        let s = CaptureSettings.default
        XCTAssertEqual(s.afterCapture, .copyAndSave)
        XCTAssertEqual(s.format, .png)
    }

    func testRoundTripsThroughDictionary() {
        var s = CaptureSettings.default
        s.afterCapture = .saveOnly
        s.format = .jpg
        let restored = CaptureSettings(dictionary: s.dictionary)
        XCTAssertEqual(restored, s)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureSettingsTests`
Expected: FAIL — `cannot find 'CaptureSettings' in scope`.

- [ ] **Step 3: Implement**

`Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`:
```swift
import Foundation

public enum AfterCaptureBehavior: String, Equatable {
    case copyOnly, saveOnly, copyAndSave
}

public enum SettingsImageFormat: String, Equatable {
    case png, jpg
}

public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat

    public static let `default` = CaptureSettings(afterCapture: .copyAndSave, format: .png)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue, "format": format.rawValue]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat) {
        self.afterCapture = afterCapture
        self.format = format
    }

    public init(dictionary: [String: String]) {
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "")
            ?? CaptureSettings.default.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "")
            ?? CaptureSettings.default.format
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureSettingsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Implement the app adapter**

`App/SettingsStore.swift`:
```swift
import Foundation
import CaptureKit

final class SettingsStore: ObservableObject {
    @Published var settings: CaptureSettings
    @Published var saveDirectory: URL

    private let defaults = UserDefaults.standard

    init() {
        let dict = defaults.dictionary(forKey: "captureSettings") as? [String: String] ?? [:]
        self.settings = dict.isEmpty ? .default : CaptureSettings(dictionary: dict)
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let saved = defaults.url(forKey: "saveDirectory") {
            self.saveDirectory = saved
        } else {
            self.saveDirectory = home.appendingPathComponent("Desktop")
        }
    }

    func persist() {
        defaults.set(settings.dictionary, forKey: "captureSettings")
        defaults.set(saveDirectory, forKey: "saveDirectory")
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Packages/CaptureKit App/SettingsStore.swift
git commit -m "feat(settings): testable CaptureSettings + UserDefaults store"
```

---

## Task 10: SelectionOverlayController (OverlayKit — MANUAL verify)

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/SelectionResult.swift`, `Packages/OverlayKit/Sources/OverlayKit/SelectionOverlayController.swift`

Context: a borderless, transparent, full-screen window per display that captures a mouse drag, draws dimming + crosshair + a live dimensions label, and returns the selected rect in global coordinates plus the display ID. Escape cancels. This is interactive UI — verified manually in Task 11.

- [ ] **Step 1: Define the result type**

`SelectionResult.swift`:
```swift
import CoreGraphics

public struct SelectionResult {
    public let globalRect: CGRect       // Cocoa global coords (points)
    public let displayID: CGDirectDisplayID
    public init(globalRect: CGRect, displayID: CGDirectDisplayID) {
        self.globalRect = globalRect
        self.displayID = displayID
    }
}
```

- [ ] **Step 2: Implement the overlay controller**

`SelectionOverlayController.swift`:
```swift
import AppKit

public final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    public init() {}

    /// Presents selection overlays on all screens; calls completion with the result (or nil if cancelled).
    public func present(completion: @escaping (SelectionResult?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let view = SelectionView(frame: screen.frame)
            view.onComplete = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
            view.onCancel = { [weak self] in self?.finish(rect: nil, screen: screen) }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard let rect, rect.width >= 1, rect.height >= 1 else { completion?(nil); return }
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        completion?(SelectionResult(globalRect: rect, displayID: displayID))
    }
}

final class SelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let s = start, let c = current else { onCancel?(); return }
        // Convert local view rect → global (window origin is screen origin here).
        let local = rectBetween(s, c)
        let global = window.map { NSRect(x: $0.frame.minX + local.minX,
                                         y: $0.frame.minY + local.minY,
                                         width: local.width, height: local.height) } ?? local
        onComplete?(global)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Escape
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let s = start, let c = current else { return }
        let sel = rectBetween(s, c)
        // Punch out the selection.
        NSColor.clear.setFill()
        sel.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: sel); path.lineWidth = 1; path.stroke()
        // Dimensions label.
        let label = "\(Int(sel.width)) × \(Int(sel.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        label.draw(at: NSPoint(x: sel.minX, y: sel.maxY + 4), withAttributes: attrs)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build --package-path Packages/OverlayKit`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): area-selection overlay window"
```

---

## Task 11: CaptureCoordinator + MenuBarController (wire everything — MANUAL verify)

**Files:**
- Create: `App/CaptureCoordinator.swift`, `App/MenuBarController.swift`
- Modify: `App/BetterScreenshotApp.swift`

- [ ] **Step 1: Implement the coordinator**

`App/CaptureCoordinator.swift`:
```swift
import AppKit
import CaptureKit
import OverlayKit

@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let settings: SettingsStore
    private let overlay = SelectionOverlayController()

    init(settings: SettingsStore) { self.settings = settings }

    func captureArea() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID)) }
        }
    }

    func captureFullscreen() {
        guard ensurePermission() else { return }
        let id = CGMainDisplayID()
        Task { await run(.fullscreen(displayID: id)) }
    }

    func captureFrontWindow() {
        guard ensurePermission() else { return }
        // Minimal v1: capture the frontmost on-screen window.
        Task {
            if let id = await frontmostWindowID() { await run(.window(windowID: id)) }
        }
    }

    private func run(_ target: CaptureTarget) async {
        do {
            let image = try await service.capture(target)
            output(image)
        } catch {
            NSLog("Capture failed: \(error)")
        }
    }

    private func output(_ image: CGImage) {
        let behavior = settings.settings.afterCapture
        let format: ImageFormat = settings.settings.format == .png ? .png : .jpg(quality: 0.9)
        if behavior == .copyOnly || behavior == .copyAndSave {
            let rep = NSBitmapImageRep(cgImage: image)
            let nsImage = NSImage(); nsImage.addRepresentation(rep)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        }
        if behavior == .saveOnly || behavior == .copyAndSave {
            guard let data = ImageEncoder.encode(image, as: format) else { return }
            let ext = settings.settings.format == .png ? "png" : "jpg"
            let name = FileNamer.fileName(for: Date(), ext: ext)
            let url = settings.saveDirectory.appendingPathComponent(name)
            try? data.write(to: url)
        }
    }

    private func ensurePermission() -> Bool {
        if PermissionManager.hasScreenRecordingPermission { return true }
        PermissionManager.requestScreenRecordingPermission()
        if !PermissionManager.hasScreenRecordingPermission {
            PermissionManager.presentDeniedAlert(); return false
        }
        return true
    }

    private func frontmostWindowID() async -> CGWindowID? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        return content?.windows.first(where: { $0.isOnScreen && $0.title?.isEmpty == false })?.windowID
    }
}
```
(Add `import ScreenCaptureKit` at the top — needed for `SCShareableContent` in `frontmostWindowID`.)

- [ ] **Step 2: Implement the menu-bar controller**

`App/MenuBarController.swift`:
```swift
import AppKit

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Area", action: #selector(area), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Window", action: #selector(window), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Fullscreen", action: #selector(full), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func area() { coordinator.captureArea() }
    @objc private func window() { coordinator.captureFrontWindow() }
    @objc private func full() { coordinator.captureFullscreen() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 3: Wire into the app delegate + register hotkeys**

Replace `App/BetterScreenshotApp.swift` with:
```swift
import SwiftUI

@main
struct BetterScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // SettingsView is created in Task 12; use EmptyView until then so this task compiles.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private var coordinator: CaptureCoordinator!
    private var menuBar: MenuBarController!
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator = CaptureCoordinator(settings: settings)
        menuBar = MenuBarController(coordinator: coordinator)
        // Defaults: ⌘⇧4 area, ⌘⇧5 window, ⌘⇧6 fullscreen.
        hotKeys.register(key: "4", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureArea() }
        }
        hotKeys.register(key: "5", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFrontWindow() }
        }
        hotKeys.register(key: "6", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFullscreen() }
        }
    }
}
```

- [ ] **Step 4: Build**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual end-to-end verification**

Run `open build/Build/Products/Debug/BetterScreenshot.app`, then verify against this checklist:
- [ ] Menu-bar camera icon appears; no Dock icon.
- [ ] First "Capture Area" triggers the macOS Screen-Recording permission prompt. Grant it, relaunch.
- [ ] "Capture Area" → dimming overlay + crosshair + live dimensions; drag a region → a PNG appears on the Desktop AND the image is on the clipboard (paste into Preview/Notes).
- [ ] ⌘⇧4 / ⌘⇧5 / ⌘⇧6 trigger area / window / fullscreen.
- [ ] Esc during area selection cancels with no file written.
- [ ] If permission is revoked in System Settings, capturing shows the guided alert instead of crashing.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app): wire capture coordinator, menu bar, and default hotkeys"
```

---

## Task 12: SettingsView (SwiftUI)

**Files:**
- Create: `App/SettingsView.swift`

- [ ] **Step 1: Implement**

`App/SettingsView.swift`:
```swift
import SwiftUI
import CaptureKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("After capture", selection: Binding(
                get: { store.settings.afterCapture },
                set: { store.settings.afterCapture = $0; store.persist() })) {
                Text("Copy to clipboard").tag(AfterCaptureBehavior.copyOnly)
                Text("Save to folder").tag(AfterCaptureBehavior.saveOnly)
                Text("Copy and save").tag(AfterCaptureBehavior.copyAndSave)
            }
            Picker("Format", selection: Binding(
                get: { store.settings.format },
                set: { store.settings.format = $0; store.persist() })) {
                Text("PNG").tag(SettingsImageFormat.png)
                Text("JPG").tag(SettingsImageFormat.jpg)
            }
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.saveDirectory = url; store.persist()
        }
    }
}
```

- [ ] **Step 2: Wire SettingsView into the app's Settings scene**

In `App/BetterScreenshotApp.swift`, replace the placeholder Settings body:
```swift
        // SettingsView is created in Task 12; use EmptyView until then so this task compiles.
        Settings { EmptyView() }
```
with:
```swift
        Settings { SettingsView(store: appDelegate.settings) }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Open the app → menu → Settings…:
- [ ] The settings window appears with the three controls.
- [ ] Changing "After capture" to "Save to folder" then capturing writes a file but does NOT touch the clipboard.
- [ ] "Change…" picks a folder; subsequent captures save there.
- [ ] Settings survive an app relaunch.

- [ ] **Step 5: Commit**

```bash
git add App/SettingsView.swift App/BetterScreenshotApp.swift
git commit -m "feat(settings): SwiftUI settings pane"
```

---

## Task 13: Full regression pass + run all tests

- [ ] **Step 1: Run the entire unit suite**

Run: `swift test --package-path Packages/CaptureKit`
Expected: ALL PASS (CaptureGeometry, ImageCropper, ImageEncoder, FileNamer, KeyCode, CaptureSettings).

- [ ] **Step 2: Clean build the app**

Run:
```bash
rm -rf build && xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Re-run the Task 11 + Task 12 manual checklists end-to-end.**

- [ ] **Step 4: Tag the milestone**

```bash
git add -A
git commit -m "chore: Plan 1 (Foundation & Capture Core) complete" --allow-empty
git tag v0.1-capture-core
```

---

## Definition of Done (Plan 1)

- `swift test` green for all CaptureKit pure logic.
- App builds clean and runs as a menu-bar agent.
- Area / window / fullscreen capture all work via menu and via ⌘⇧4/5/6.
- Output respects the after-capture setting (copy / save / both), chosen format, and save folder.
- Screen-Recording permission is handled gracefully (prompt → guided alert, no crashes).
- Esc cancels area selection cleanly.

**Next:** Plan 2 (Quick Access Overlay) replaces the "straight to copy/save" path with the post-capture floating thumbnail, then Plan 3 adds the annotation editor.
```
