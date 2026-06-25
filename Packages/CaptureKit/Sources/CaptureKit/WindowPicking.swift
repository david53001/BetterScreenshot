import Foundation
import CoreGraphics

/// One on-screen window for hit-testing. `frame` is in Cocoa bottom-left global
/// coordinates (convert from CGWindowList bounds via `WindowPicking.cocoaFrame`).
public struct PickableWindow: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let title: String?
    public let layer: Int
    public let ownerPID: pid_t

    public init(id: UInt32, frame: CGRect, title: String?, layer: Int, ownerPID: pid_t) {
        self.id = id
        self.frame = frame
        self.title = title
        self.layer = layer
        self.ownerPID = ownerPID
    }
}

public enum WindowPicking {
    /// `windows` must be **front-to-back ordered** (caller's contract, e.g. from
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)`). Returns the
    /// front-most normal window (layer 0), not owned by `excludingPID`, whose
    /// frame contains `point`. nil on a miss.
    public static func topmost(at point: CGPoint, windows: [PickableWindow],
                               excludingPID: pid_t) -> PickableWindow? {
        for w in windows where w.layer == 0 && w.ownerPID != excludingPID {
            if w.frame.contains(point) { return w }
        }
        return nil
    }

    /// Convert a top-left-origin global rect (CGWindowList bounds) to Cocoa
    /// bottom-left global coordinates, given the primary display's height.
    public static func cocoaFrame(fromTopLeft frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.minY - frame.height,
               width: frame.width, height: frame.height)
    }
}
