import Foundation

/// Tiny 3D vector for sphere-eye math. Foundation-only; no SceneKit / RealityKit.
public struct Vec3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public func normalized() -> Vec3 {
        let len = length
        if len <= 1e-12 { return Vec3(0, 0, 1) }
        return Vec3(x / len, y / len, z / len)
    }

    public static func dot(_ a: Vec3, _ b: Vec3) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    public static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
        Vec3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func * (lhs: Vec3, rhs: Double) -> Vec3 {
        Vec3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}

/// One eye's spherical pose. The shell/sclera ellipses stay fixed; this is a
/// rotation of the globe toward a shared 3D target, not a 2D pupil slide.
public struct SphericalEyePose: Equatable, Sendable {
    /// Unit gaze direction in eye space: +X right, +Y down (canvas), +Z toward camera.
    public var direction: Vec3
    /// Orthographic projection of the iris-disc center, in canvas pixels.
    public var projectedIrisCenter: Point2D
    public var projectedPupilCenter: Point2D
    /// `direction.z` in (0, 1]. Smaller values mean more foreshortening.
    public var facing: Double
    /// Iris cap half-angle (radians) on the unit sphere.
    public var irisAngularRadius: Double
    public var pupilAngularRadius: Double
    /// Projected iris-plane axes in canvas pixels (unit-circle → ellipse).
    public var irisAxisU: Point2D
    public var irisAxisV: Point2D
    public var projectedPupilAxisU: Point2D
    public var projectedPupilAxisV: Point2D
    public var scleraCenter: Point2D
    public var shellCenter: Point2D
}

/// Shared 3D gaze for both eyes. Public API is the target point on the
/// platter plus `pose(spec:target:)`. Intentionally not SceneKit / RealityKit:
/// the math is small, testable on the Core target, and available on macOS 13.
public enum SphereGaze {
    /// Gaze is built in *ellipse-normalized* eye space: X/Y are canvas
    /// offsets divided by the sclera radii, Z is `depthInRadii` toward the
    /// camera. This keeps default and far-sector angles on a continuous range
    /// instead of slamming every disc point into a single foreshorten value.
    /// The retired 073448 `platterDepth = 820` + 48° hard clamp is why the
    /// iris sat on the lower rim and most frames shared facing = cos(48°).
    public static let depthInRadii: Double = 5.0

    /// Kept as `depthInRadii` times a typical sclera radius, only for logs.
    public static var platterDepth: Double { depthInRadii * 280 }

    /// Soft safety so a target cannot flip the globe to look backward.
    /// Not an operating clamp for ordinary disc points.
    public static let maxSafePolarAngle: Double = 72.0 * Double.pi / 180.0

    /// Backward-compatible name used by older tests; same as `maxSafePolarAngle`.
    public static var maxPolarAngle: Double { maxSafePolarAngle }

    /// Stable default target: the current largest chartable sector (by bytes).
    /// For the isolated example set that is Movies / 影片 / 72 GB. Not an
    /// automatic L lock, and not a card-layout change.
    public static func defaultTarget(sectors: [ChartSector], layout: SemicircleLayout) -> Point2D {
        guard let largest = sectors.max(by: { $0.bytes < $1.bytes }) else {
            return layout.pointOnRay(degrees: 207, radiusFraction: 0.58)
        }
        return layout.visibleInteriorPoint(
            startDegrees: largest.startDegrees,
            endDegrees: largest.endDegrees
        )
    }

    public static func defaultTargetID(sectors: [ChartSector]) -> String? {
        sectors.max(by: { $0.bytes < $1.bytes })?.id
    }

    public static func pose(spec: VectorEyeSpec, target: Point2D) -> SphericalEyePose {
        let center = spec.sclera.center
        let rx = spec.sclera.radiusX
        let ry = spec.sclera.radiusY
        let rz = (rx + ry) / 2
        var dir = Vec3(
            (target.x - center.x) / rx,
            (target.y - center.y) / ry,
            depthInRadii
        ).normalized()
        dir = softLimitBackHemisphere(dir)

        let irisAlpha = asin(min(spec.irisRadius / rz, 0.92))
        let pupilAlpha = asin(min(spec.pupilRadius / rz, 0.70))
        let uUnit = axisU(dir)
        let vUnit = axisV(dir, u: uUnit)
        let irisCenter = dir * cos(irisAlpha)
        let pupilCenter = dir * cos(pupilAlpha)

        return SphericalEyePose(
            direction: dir,
            projectedIrisCenter: Point2D(
                x: center.x + irisCenter.x * rx,
                y: center.y + irisCenter.y * ry
            ),
            projectedPupilCenter: Point2D(
                x: center.x + pupilCenter.x * rx,
                y: center.y + pupilCenter.y * ry
            ),
            facing: dir.z,
            irisAngularRadius: irisAlpha,
            pupilAngularRadius: pupilAlpha,
            irisAxisU: Point2D(x: uUnit.x * sin(irisAlpha) * rx, y: uUnit.y * sin(irisAlpha) * ry),
            irisAxisV: Point2D(x: vUnit.x * sin(irisAlpha) * rx, y: vUnit.y * sin(irisAlpha) * ry),
            projectedPupilAxisU: Point2D(x: uUnit.x * sin(pupilAlpha) * rx, y: uUnit.y * sin(pupilAlpha) * ry),
            projectedPupilAxisV: Point2D(x: vUnit.x * sin(pupilAlpha) * rx, y: vUnit.y * sin(pupilAlpha) * ry),
            scleraCenter: center,
            shellCenter: spec.shell.center
        )
    }

    public static let lightDirection = SphereShade.light

    /// Tight warm contact shadow under one globe. Replaces the former wide
    /// dark-red residual oval `SelectedBaseArtwork.eyeShadowMin/Max`.
    public static func contactShadow(spec: VectorEyeSpec) -> AxisAlignedEllipse {
        let c = spec.shell.center
        return AxisAlignedEllipse(
            center: Point2D(x: c.x, y: c.y + spec.shell.radiusY * 0.74),
            radiusX: spec.shell.radiusX * 0.78,
            radiusY: spec.shell.radiusY * 0.18
        )
    }

    private static func softLimitBackHemisphere(_ dir: Vec3) -> Vec3 {
        var d = dir
        if d.z < 0 {
            d = Vec3(d.x, d.y, 0.08).normalized()
        }
        let xy = (d.x * d.x + d.y * d.y).squareRoot()
        let maxXY = sin(maxSafePolarAngle)
        if xy > maxXY {
            let s = maxXY / xy
            d = Vec3(d.x * s, d.y * s, cos(maxSafePolarAngle)).normalized()
        }
        return d
    }

    private static func axisU(_ dir: Vec3) -> Vec3 {
        let worldUp = Vec3(0, 1, 0)
        var u = Vec3.cross(worldUp, dir)
        if u.length < 1e-6 {
            u = Vec3(1, 0, 0)
        }
        return u.normalized()
    }

    private static func axisV(_ dir: Vec3, u: Vec3) -> Vec3 {
        Vec3.cross(dir, u).normalized()
    }
}
