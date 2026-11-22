import Foundation

public enum ActiveInput: String, Equatable, Sendable {
    case none
    case pointer
    case keyboard
}

/// Pointer preview P (H), keyboard preview K, lock L, and last active input.
/// Display is T ?? L ?? overview, where T is only the preview of the active input
/// (no cross-source fallback).
public struct InteractionState: Equatable, Sendable {
    public var pointerPreviewID: String?
    public var keyboardPreviewID: String?
    public var lockedID: String?
    /// Retained keyboard focus so later arrow/Tab can resume, but it is not a live preview
    /// unless activeInput == .keyboard.
    public var retainedKeyboardFocusID: String?
    public var activeInput: ActiveInput
    /// Independent range identity. Preview and lock never change it and never start observation.
    public var actualObservationID: String?
    /// Latest pointer location in canvas space. Updated on every move, independent of H/L.
    /// Nil when the pointer is outside the window or has never entered.
    public var pointerLocation: Point2D?
    /// Incremented when display identity (H/K/L / active input) changes, so stale
    /// animation callbacks cannot write back. Pure pointer-location updates do not bump it.
    public var generation: UInt64

    public static let initial = InteractionState(
        pointerPreviewID: nil,
        keyboardPreviewID: nil,
        lockedID: nil,
        retainedKeyboardFocusID: nil,
        activeInput: .none,
        actualObservationID: nil,
        pointerLocation: nil,
        generation: 0
    )

    public var temporaryID: String? {
        switch activeInput {
        case .pointer: return pointerPreviewID
        case .keyboard: return keyboardPreviewID
        case .none: return nil
        }
    }

    /// Display priority: active preview (H/K of the current source) > L > overview.
    public var displayedID: String? {
        temporaryID ?? lockedID
    }

    public mutating func bump() {
        generation &+= 1
    }
}

public struct InteractionSession: Equatable, Sendable {
    public var state: InteractionState
    public var hits: HitTesting
    public var snapshot: DemoSnapshot
    public var chartability: Chartability
    public var layout: SemicircleLayout

    public init(snapshot: DemoSnapshot, layout: SemicircleLayout = .selectedBase, state: InteractionState = .initial) {
        self.snapshot = snapshot
        self.layout = layout
        self.chartability = ChartabilityGate.evaluate(snapshot)
        self.hits = HitTesting(layout: layout, sectors: chartability.sectors)
        self.state = state
    }

    public var infoFactory: InfoFactory {
        InfoFactory(snapshot: snapshot, chartability: chartability)
    }

    public var displayedInfo: DirectoryInfo {
        infoFactory.info(for: state.displayedID)
    }

    public var displayedSector: ChartSector? {
        guard let id = state.displayedID else { return nil }
        return hits.sector(id: id)
    }

    public var traversableIDs: [String] {
        chartability.sectors.map(\.id)
    }

    /// Real pointer movement. Stationary hover must not call this just to steal keyboard preview.
    public mutating func pointerMoved(to point: Point2D) {
        let result = hits.hit(at: point)
        let newP: String?
        switch result {
        case .none:
            newP = nil
        case .sector(let id):
            newP = id
        }
        // Continuous pointer state: every move records the real coordinate,
        // even when H stays on the same sector (eyes follow the point, not a sector center).
        state.pointerLocation = point
        let identityChanged = state.activeInput != .pointer
            || state.keyboardPreviewID != nil
            || state.pointerPreviewID != newP
        state.activeInput = .pointer
        state.keyboardPreviewID = nil
        state.pointerPreviewID = newP
        if identityChanged {
            state.bump()
        }
    }

    /// Pointer actually left the full program window (not the disc or fitted canvas). Does not clear a still-valid keyboard preview.
    /// The eye also stops tracking (no pointer target).
    public mutating func pointerExitedVisibleArea() {
        state.pointerLocation = nil
        state.pointerPreviewID = nil
        if state.activeInput == .pointer {
            state.activeInput = .none
        }
        state.bump()
    }

    public mutating func pointerClicked(at point: Point2D) {
        pointerMoved(to: point)
        if case .sector(let id) = hits.hit(at: point) {
            lock(id)
        }
    }

    /// Repeat lock of the same id keeps L. This checkpoint does not add an unlock gesture.
    /// An insufficient (non-chartable) snapshot has no lockable proportion sectors.
    public mutating func lock(_ id: String) {
        guard chartability.isChartable, traversableIDs.contains(id) else { return }
        state.lockedID = id
        state.bump()
    }

    public mutating func enterPressed() {
        guard state.activeInput == .keyboard, let id = state.keyboardPreviewID else { return }
        lock(id)
    }

    public enum KeyboardDirection: Equatable, Sendable {
        case next
        case previous
    }

    /// Tab / arrow: immediately switch to keyboard, clear P, preview a valid focus.
    /// A still pointer cannot take this back.
    public mutating func moveKeyboardFocus(_ direction: KeyboardDirection) {
        let ids = traversableIDs
        guard !ids.isEmpty else { return }
        let current = state.keyboardPreviewID ?? state.retainedKeyboardFocusID ?? state.displayedID
        let next: String
        if let current, let idx = ids.firstIndex(of: current) {
            switch direction {
            case .next:
                next = ids[(idx + 1) % ids.count]
            case .previous:
                next = ids[(idx - 1 + ids.count) % ids.count]
            }
        } else {
            next = direction == .previous ? ids.last! : ids.first!
        }
        state.activeInput = .keyboard
        state.pointerPreviewID = nil
        state.keyboardPreviewID = next
        state.retainedKeyboardFocusID = next
        state.bump()
    }

    /// Keyboard focus left the component (not merely a still pointer).
    public mutating func keyboardFocusLeftComponent() {
        state.keyboardPreviewID = nil
        if state.activeInput == .keyboard {
            state.activeInput = .none
        }
        state.bump()
    }

    /// Window lost key / focus: clear P and K, keep L, activeInput becomes none.
    /// Restoring focus does not revive old previews.
    public mutating func windowLostFocus() {
        // Key focus is not pointer exit. Keep the last window-local gaze point;
        // activeAlways local tracking will update/clear it on movement/exit.
        state.pointerPreviewID = nil
        state.keyboardPreviewID = nil
        state.activeInput = .none
        state.bump()
    }

    public mutating func windowGainedFocus() {
        // Explicitly do nothing to previews. Wait for a new active input.
    }

    /// Stale animation / transition callbacks must pass this before writing presentation.
    public func isCurrent(generation: UInt64) -> Bool {
        generation == state.generation
    }
}
