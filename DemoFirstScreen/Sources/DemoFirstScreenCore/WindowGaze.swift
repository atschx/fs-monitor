import Foundation

/// 15:53 rule: the event surface is the WHOLE local window, including letterbox.
/// Artwork keeps its original 4:3 geometry. Letterbox maps outside canvas rather
/// than clamping to an edge or reusing a stale disc target. No screen coordinates.
public struct WindowCanvasMap: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var scale: Double { min(width / 2400, height / 1800) }
    public var origin: Point2D {
        Point2D(x: (width - 2400 * scale) / 2, y: (height - 1800 * scale) / 2)
    }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public func contains(_ p: Point2D) -> Bool {
        width > 0 && height > 0 && p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }
    public func canvasPoint(_ p: Point2D) -> Point2D {
        guard scale > 0 else { return p }
        return Point2D(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }
}

/// Explicit shared-target clock, not withAnimation around an opaque bitmap.
/// Critically damped exact step: pointer updates replace the goal, NEVER restart
/// a 240ms animation deadline. Both eyes use this one presented point. At rest a
/// finite position/velocity epsilon settles exactly. Reduce Motion is a snap.
public struct SharedGazeMotion: Equatable, Sendable {
    public private(set) var position: Point2D
    public private(set) var target: Point2D
    public private(set) var velocity = Point2D(x: 0, y: 0)
    public private(set) var time: Double
    public private(set) var frameIndex: UInt64 = 0
    public private(set) var reduced: Bool
    public var settled: Bool { position == target && velocity == Point2D(x: 0, y: 0) }
    public init(target: Point2D, time: Double = 0, reduced: Bool = false) {
        self.position = target; self.target = target; self.time = time; self.reduced = reduced
    }
    public mutating func retarget(_ target: Point2D, at now: Double, reduced: Bool) {
        _ = advance(to: now)
        self.target = target; self.reduced = reduced
        if reduced { position = target; velocity = Point2D(x: 0, y: 0) }
    }
    @discardableResult public mutating func advance(to now: Double) -> Point2D {
        let dt = max(0, now - time)
        time = max(time, now)
        guard dt > 0 else { return position }
        frameIndex &+= 1
        if reduced { position = target; velocity = Point2D(x: 0, y: 0); return position }
        let omega = 24.0
        let decay = exp(-omega * dt)
        func axis(_ p: Double, _ v: Double, _ g: Double) -> (Double, Double) {
            let delta = p - g, c = v + omega * delta
            return (g + (delta + c * dt) * decay, (v - omega * c * dt) * decay)
        }
        let x = axis(position.x, velocity.x, target.x), y = axis(position.y, velocity.y, target.y)
        position = Point2D(x: x.0, y: y.0); velocity = Point2D(x: x.1, y: y.1)
        if hypot(position.x-target.x, position.y-target.y) < 0.20 && hypot(velocity.x, velocity.y) < 2 {
            position = target; velocity = Point2D(x: 0, y: 0)
        }
        return position
    }
}
