import CoreGraphics

public struct SelectionResult {
    public let globalRect: CGRect       // Cocoa global coords (points)
    public let displayID: CGDirectDisplayID
    public init(globalRect: CGRect, displayID: CGDirectDisplayID) {
        self.globalRect = globalRect
        self.displayID = displayID
    }
}
