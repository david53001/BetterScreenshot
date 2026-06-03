import TestKit
import CoreGraphics
@testable import CaptureKit

let captureGeometryTests: [TestCase] = [
    TestCase("convertsGlobalRectToTopLeftPixelRect") { t in
        // Display: 1440x900 pt at scale 2 → 2880x1800 px, origin (0,0).
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Selection in Cocoa (bottom-left origin): x100 y100 w200 h150.
        let selection = CGRect(x: 100, y: 100, width: 200, height: 150)
        let px = CaptureGeometry.pixelRect(forGlobalRect: selection,
                                           inDisplayFrame: display, scale: 2)
        // x = (100-0)*2 = 200; top y = (900 - (100+150))*2 = 1300; w=400; h=300
        t.equal(px, CGRect(x: 200, y: 1300, width: 400, height: 300))
    },
    TestCase("handlesNonZeroDisplayOrigin") { t in
        let display = CGRect(x: 1440, y: 0, width: 1920, height: 1080) // second display
        let selection = CGRect(x: 1540, y: 80, width: 100, height: 100)
        let px = CaptureGeometry.pixelRect(forGlobalRect: selection,
                                           inDisplayFrame: display, scale: 1)
        // x=(1540-1440)=100; top y=(1080-(80+100))=900; w=100; h=100
        t.equal(px, CGRect(x: 100, y: 900, width: 100, height: 100))
    },
]
