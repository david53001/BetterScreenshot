import Foundation

/// Recording lifecycle. Pure state machine: `transition` applies an event only
/// when legal, so callers (the ⌘⇧5 toggle) can't corrupt the lifecycle.
public enum RecorderState: Equatable {
    case idle
    case armed                       // record strip showing
    case recording(started: Date)
    case finishing                   // writer finalizing — new commands rejected

    public enum Event: Equatable {
        case arm                     // show the strip
        case begin(Date)             // capture started
        case finish                  // stop requested
        case reset                   // back to idle (finalized or cancelled)
    }

    /// Applies `event` if legal; returns whether the state changed.
    @discardableResult
    public mutating func transition(_ event: Event) -> Bool {
        switch (self, event) {
        case (.idle, .arm):                self = .armed
        case (.armed, .begin(let date)):   self = .recording(started: date)
        case (.armed, .reset):             self = .idle
        case (.recording, .finish):        self = .finishing
        case (.finishing, .reset):         self = .idle
        default:                           return false
        }
        return true
    }

    /// "m:ss" while recording; nil otherwise.
    public func elapsedString(now: Date) -> String? {
        guard case .recording(let started) = self else { return nil }
        let secs = max(0, Int(now.timeIntervalSince(started)))
        return "\(secs / 60):" + String(format: "%02d", secs % 60)
    }
}
