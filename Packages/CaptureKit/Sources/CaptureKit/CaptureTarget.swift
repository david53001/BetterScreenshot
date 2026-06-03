import CoreGraphics

public enum CaptureTarget {
    /// Selection rect in Cocoa global coordinates (points), plus the display it lives on.
    case area(rect: CGRect, displayID: CGDirectDisplayID)
    case fullscreen(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID)
}
