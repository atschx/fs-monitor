import Foundation

/// Fixed D2 eye *shape* (shell / sclera ellipses, iris and pupil radii).
/// Placement is the documented lift used since 064745; this is not a new eye
/// outline and not an upscaled bitmap of the 218×127 D2-1024 crop.
///
/// Spherical rotation and procedural iris material live in `SphereGaze` /
/// `DemoRootView.drawSphericalEye`. Shell and sclera ellipses stay fixed.
public struct VectorEyeSpec: Equatable, Sendable {
    public var shell: AxisAlignedEllipse
    public var sclera: AxisAlignedEllipse
    public var irisRestCenter: Point2D
    public var irisRadius: Double
    public var pupilRadius: Double
    public var highlightOffset: Point2D
    public var highlightRadius: Double
    public var highlight2Offset: Point2D
    public var highlight2Radius: Double
    /// Radius used for the 18% travel cap. Matches the documented left exclusion rx.
    public var scleraRadiusForClamp: Double

    public func irisCenter(offset: Point2D) -> Point2D {
        Point2D(x: irisRestCenter.x + offset.x, y: irisRestCenter.y + offset.y)
    }

    /// Documented left exclusion / iris rest, y lifted by EyePlacement.canvasLift.
    public static let left = VectorEyeSpec(
        shell: AxisAlignedEllipse(center: Point2D(x: 888, y: 378), radiusX: 318, radiusY: 354),
        sclera: AxisAlignedEllipse(center: Point2D(x: 894, y: 456), radiusX: 270, radiusY: 292),
        irisRestCenter: Point2D(x: 894, y: 486),
        irisRadius: 176,
        pupilRadius: 72,
        highlightOffset: Point2D(x: -58, y: -62),
        highlightRadius: 44,
        highlight2Offset: Point2D(x: 36, y: 28),
        highlight2Radius: 16,
        scleraRadiusForClamp: 318
    )

    /// Documented right exclusion / iris rest, y lifted by EyePlacement.canvasLift.
    public static let right = VectorEyeSpec(
        shell: AxisAlignedEllipse(center: Point2D(x: 1518, y: 432), radiusX: 324, radiusY: 336),
        sclera: AxisAlignedEllipse(center: Point2D(x: 1428, y: 508), radiusX: 276, radiusY: 286),
        irisRestCenter: Point2D(x: 1428, y: 552),
        irisRadius: 184,
        pupilRadius: 76,
        highlightOffset: Point2D(x: -60, y: -64),
        highlightRadius: 46,
        highlight2Offset: Point2D(x: 38, y: 30),
        highlight2Radius: 16,
        scleraRadiusForClamp: 318
    )

    /// Lid / sclera / iris hex colors taken from the D2 rest appearance,
    /// used by the vector redraw (not a sharpened bitmap).
    public enum Fill {
        public static let lid = "#e6cbb3"
        public static let lidRim = "#c4a07c"
        public static let lidCrease = "#9a6d4c"
        public static let sclera = "#fbf6ee"
        public static let scleraEdge = "#e4d6c2"
        public static let irisOuter = "#6b3d1c"
        public static let irisMid = "#8d5226"
        public static let irisInner = "#3a1c0c"
        public static let irisLimbusGold = "#c49a52"
        public static let irisLimbusEdge = "#4a2410"
        public static let irisFiber = "#a86a35"
        public static let irisFiberDark = "#5c3014"
        public static let pupil = "#140c08"
        public static let highlight = "#ffffff"
        public static let scleraShade = "#e8d8c4"
    }
}
