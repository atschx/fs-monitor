import Foundation

/// 2D point in canvas space. y grows downward, matching the 2400×1800 design canvas.
/// Pure Foundation (no CoreGraphics) so the model can later be tested on Linux.
public struct Point2D: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point2D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Axis-aligned ellipse in canvas space. Used only as a display / hit mask.
/// It never replaces the mathematical semicircle as the angular denominator.
public struct AxisAlignedEllipse: Equatable, Sendable {
    public var center: Point2D
    public var radiusX: Double
    public var radiusY: Double

    public init(center: Point2D, radiusX: Double, radiusY: Double) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
    }

    /// Inclusive bounding box (minX, minY, maxX, maxY) as recorded in selected-base geometry.json.
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.center = Point2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        self.radiusX = (maxX - minX) / 2
        self.radiusY = (maxY - minY) / 2
    }

    public var minX: Double { center.x - radiusX }
    public var minY: Double { center.y - radiusY }
    public var maxX: Double { center.x + radiusX }
    public var maxY: Double { center.y + radiusY }

    public func contains(_ point: Point2D) -> Bool {
        let nx = (point.x - center.x) / radiusX
        let ny = (point.y - center.y) / radiusY
        return nx * nx + ny * ny <= 1
    }
}

/// Optional extra left/right inset, for tests of the configurable crop path only.
/// Selected-base display crop is the 2400×1800 canvas against radius 3000 plus the
/// documented platter ellipse — not a newly invented SideCrop ratio.
public struct SideCrop: Equatable, Sendable {
    public var left: Double
    public var right: Double

    public static let none = SideCrop(left: 0, right: 0)

    public var isPendingUnchangedDefault: Bool { left == 0 && right == 0 }

    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }
}

/// Fixed selected-base geometry: complete upper mathematical semicircle, center on the bottom edge.
/// Angles live on that true circle. The visible platter is a documented display clip only.
/// Decorative eye/hub do not move the angle origin.
public struct SemicircleLayout: Equatable, Sendable {
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var center: Point2D
    public var radius: Double
    public var sideCrop: SideCrop

    /// Documented inner platter clip from selected-base-0353-frame02/geometry.json
    /// `clip_ellipse_output`: [-182, 548, 2582, 2320]. Display mask only.
    public var platterClipEllipse: AxisAlignedEllipse

    /// Documented outer platter ellipse: [-250, 502, 2650, 2370]. Decorative shell rim, not angle math.
    public var outerPlatterEllipse: AxisAlignedEllipse

    /// Hub exclusion: notes locate the overlay at (966,1664)–(1435,1800) on the 2400×1800 canvas,
    /// a half-disk centered on the bottom midpoint. Not a control.
    public var hubRadius: Double

    /// Eye exclusion ellipses, taken from the documented D2 crop placement (not a new layout).
    public var eyeExclusions: [AxisAlignedEllipse]

    /// Origin is a single point (the angle origin). Excluded and non-penetrable.
    public var originHitTolerance: Double

    public struct Circle: Equatable, Sendable {
        public var center: Point2D
        public var radius: Double
        public init(center: Point2D, radius: Double) {
            self.center = center
            self.radius = radius
        }

        public func contains(_ point: Point2D) -> Bool {
            point.distance(to: center) <= radius
        }
    }

    /// Canonical selected-base canvas from selected-base-0353-frame02/geometry.json:
    /// 2400×1800, center (1200,1800), true-circle radius 3000.
    /// The 2400×1800 frame is the display crop (diameter overflows 1800px per side;
    /// the top of the semicircle is 1200px above the frame). Angles are not recomputed
    /// from clipped area. This is not the semicircle-bold r=1900 candidate, and not
    /// an invented new ratio.
    public static let selectedBase = SemicircleLayout(
        canvasWidth: 2400,
        canvasHeight: 1800,
        center: Point2D(x: 1200, y: 1800),
        radius: 3000,
        sideCrop: .none,
        platterClipEllipse: AxisAlignedEllipse(minX: -182, minY: 548, maxX: 2582, maxY: 2320),
        outerPlatterEllipse: AxisAlignedEllipse(minX: -250, minY: 502, maxX: 2650, maxY: 2370),
        hubRadius: 235,
        eyeExclusions: [
            // D2 crop placement, lifted by EyePlacement.canvasLift (56) so the
            // left globe top is y=24, not −32. Radii unchanged; binocular span
            // remains 1272 / 2400 ≈ 53%. Mask ellipses from draw_review.py.
            AxisAlignedEllipse(center: Point2D(x: 888, y: 378), radiusX: 318, radiusY: 354),
            AxisAlignedEllipse(center: Point2D(x: 1518, y: 432), radiusX: 324, radiusY: 336)
        ],
        originHitTolerance: 0.75
    )

    public var cropMinX: Double { sideCrop.left }
    public var cropMaxX: Double { canvasWidth - sideCrop.right }
    public var cropMinY: Double { 0 }
    public var cropMaxY: Double { canvasHeight }

    public func isInsideCanvas(_ point: Point2D) -> Bool {
        point.x >= 0 && point.x <= canvasWidth && point.y >= 0 && point.y <= canvasHeight
    }

    public func isInsideVisibleCrop(_ point: Point2D) -> Bool {
        point.x >= cropMinX && point.x < cropMaxX && point.y >= cropMinY && point.y < cropMaxY
    }

    /// Upper mathematical semicircle, including the diameter, excluding the exterior.
    /// Uses `radius` of the true circle. Not the platter ellipse.
    public func isInsideMathematicalSemicircle(_ point: Point2D) -> Bool {
        let d = point.distance(to: center)
        if d > radius { return false }
        // Upper half in y-down coordinates: y <= center.y (on or above the bottom diameter).
        return point.y <= center.y
    }

    /// Visible platter face = documented inner clip ellipse. Not a circular radius,
    /// and not a transform that changes sector angles.
    public func isInsidePlatterFace(_ point: Point2D) -> Bool {
        platterClipEllipse.contains(point) && point.y <= center.y
    }

    public func isOnOrigin(_ point: Point2D) -> Bool {
        point.distance(to: center) <= originHitTolerance
    }

    public func isInsideHub(_ point: Point2D) -> Bool {
        point.distance(to: center) <= hubRadius && point.y <= center.y
    }

    public func isInsideEye(_ point: Point2D) -> Bool {
        eyeExclusions.contains { $0.contains(point) }
    }

    public func isDecorativeExclusion(_ point: Point2D) -> Bool {
        isOnOrigin(point) || isInsideHub(point) || isInsideEye(point)
    }

    /// Pillow / y-down convention: 0° at +x (right), 90° down, 180° left, 270° up.
    /// The upper semicircle occupies 180°...360°.
    public func polarAngleDegrees(of point: Point2D) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var deg = atan2(dy, dx) * 180.0 / Double.pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Distance from the angle origin along `degrees` to the inner clip ellipse, if it hits.
    /// Display geometry only; does not alter sector start/end angles.
    public func radiusToPlatterClip(atDegrees degrees: Double) -> Double? {
        let rad = degrees * Double.pi / 180.0
        let dx = cos(rad)
        let dy = sin(rad)
        let ux = dx / platterClipEllipse.radiusX
        let uy = dy / platterClipEllipse.radiusY
        let vx = (center.x - platterClipEllipse.center.x) / platterClipEllipse.radiusX
        let vy = (center.y - platterClipEllipse.center.y) / platterClipEllipse.radiusY
        let a = ux * ux + uy * uy
        let b = 2 * (ux * vx + uy * vy)
        let c = vx * vx + vy * vy - 1
        let disc = b * b - 4 * a * c
        if disc < 0 || a == 0 { return nil }
        let root = disc.squareRoot()
        let t1 = (-b - root) / (2 * a)
        let t2 = (-b + root) / (2 * a)
        let candidates = [t1, t2].filter { $0 > 0 }
        return candidates.min()
    }

    /// Interior point of the visible portion of a sector, used as a gaze target.
    /// Not the possibly off-canvas geometric center of a full sector.
    public func visibleInteriorPoint(startDegrees: Double, endDegrees: Double) -> Point2D {
        let mid = (startDegrees + endDegrees) / 2
        let rad = mid * Double.pi / 180.0
        let maxR = radiusToPlatterClip(atDegrees: mid) ?? min(platterClipEllipse.radiusX, platterClipEllipse.radiusY)
        func point(at fraction: Double) -> Point2D {
            let r = maxR * fraction
            return Point2D(
                x: center.x + cos(rad) * r,
                y: center.y + sin(rad) * r
            )
        }
        var p = point(at: 0.62)
        if isInsideEye(p) || isInsideHub(p) || !isInsidePlatterFace(p) || !isInsideVisibleCrop(p) {
            p = point(at: 0.40)
        }
        return p
    }

    /// A point along a polar ray, at `radiusFraction` of the visible clip radius.
    /// Used for continuous gaze tests and sector-local info anchors. Does not change angles.
    public func pointOnRay(degrees: Double, radiusFraction: Double) -> Point2D {
        let rad = degrees * Double.pi / 180.0
        let maxR = radiusToPlatterClip(atDegrees: degrees)
            ?? min(platterClipEllipse.radiusX, platterClipEllipse.radiusY)
        let r = maxR * radiusFraction
        return Point2D(
            x: center.x + cos(rad) * r,
            y: center.y + sin(rad) * r
        )
    }
}

/// Placement of documented D2 artwork on the 2400×1800 canvas.
/// Numbers are 2× the 1200×900 native recipes in draw_review.py / draw_warm.py.
public enum SelectedBaseArtwork {
    public static let eyesOrigin = Point2D(x: 546, y: 12)
    public static let eyesSize = Point2D(x: 1308, y: 762)
    public static let eyeShadowMin = Point2D(x: 530, y: 560)
    public static let eyeShadowMax = Point2D(x: 1914, y: 754)
    public static let hubOrigin = Point2D(x: 1000, y: 1664)
    public static let hubSize = Point2D(x: 400, y: 354)
    public static let hubShadowLayerOrigin = Point2D(x: 940, y: 1665)
    public static let hubShadowLayerSize = Point2D(x: 520, y: 260)
    public static let hubShadowEllipse = (minX: 45.0, minY: 100.0, maxX: 475.0, maxY: 248.0)
}

public struct PupilMotion: Equatable, Sendable {
    /// Retired 2D pupil-slide cap. Drawing and presentation use `SphereGaze`
    /// (spherical polar clamp) instead. Kept only so older call sites compile.
    public static let maxDisplacementFraction: Double = 0.18

    /// Offset in the eye-white local coordinates, clamped to 18% of available radius.
    /// The eye shell itself does not move or scale.
    public static func offset(
        from eyeCenter: Point2D,
        toward target: Point2D?,
        scleraRadius: Double
    ) -> Point2D {
        guard let target else { return Point2D(x: 0, y: 0) }
        let dx = target.x - eyeCenter.x
        let dy = target.y - eyeCenter.y
        let dist = (dx * dx + dy * dy).squareRoot()
        let maxD = scleraRadius * maxDisplacementFraction
        if dist <= 0 { return Point2D(x: 0, y: 0) }
        if dist <= maxD { return Point2D(x: dx, y: dy) }
        let s = maxD / dist
        return Point2D(x: dx * s, y: dy * s)
    }
}

/// On-screen info block placement. The anchor is stable for a given sector
/// (it does not chase every pointer pixel inside that sector) and sits near
/// that sector, on its side of the semicircle, clamped to the canvas margins.
public struct InfoPlacement: Equatable, Sendable {
    public var isVisible: Bool
    public var center: Point2D
    public var identityID: String?

    public static let hidden = InfoPlacement(isVisible: false, center: Point2D(x: 0, y: 0), identityID: nil)

    public static let defaultBoxWidth: Double = 560
    public static let defaultBoxHeight: Double = 320
    public static let defaultMargin: Double = 72

    public static func make(
        sector: ChartSector?,
        layout: SemicircleLayout = .selectedBase,
        boxWidth: Double = defaultBoxWidth,
        boxHeight: Double = defaultBoxHeight,
        margin: Double = defaultMargin
    ) -> InfoPlacement {
        guard let sector else { return .hidden }
        let mid = (sector.startDegrees + sector.endDegrees) / 2
        var p = layout.visibleInteriorPoint(startDegrees: sector.startDegrees, endDegrees: sector.endDegrees)
        let side: Double
        if mid < 270 {
            side = -1
        } else if mid > 270 {
            side = 1
        } else {
            side = 0
        }
        // Side-adaptive offset: keep the block near the sector, not pinned to the first-sector left.
        p.x += side * 90
        let halfW = boxWidth / 2
        let halfH = boxHeight / 2
        p.x = min(max(p.x, margin + halfW), layout.canvasWidth - margin - halfW)
        p.y = min(max(p.y, margin + halfH), layout.canvasHeight - margin - halfH)
        if layout.isInsideEye(p) {
            p.y = min(p.y + 220, layout.canvasHeight - margin - halfH)
        }
        if layout.isInsideHub(p) {
            let lifted = layout.center.y - layout.hubRadius - halfH - 24
            p.y = min(max(lifted, margin + halfH), layout.canvasHeight - margin - halfH)
        }
        return InfoPlacement(isVisible: true, center: p, identityID: sector.id)
    }

    /// True when the axis-aligned info box stays inside the canvas plus margin.
    public func isClamped(to layout: SemicircleLayout, boxWidth: Double = defaultBoxWidth, boxHeight: Double = defaultBoxHeight, margin: Double = defaultMargin) -> Bool {
        guard isVisible else { return true }
        let halfW = boxWidth / 2
        let halfH = boxHeight / 2
        return center.x - halfW >= margin - 1e-9
            && center.x + halfW <= layout.canvasWidth - margin + 1e-9
            && center.y - halfH >= margin - 1e-9
            && center.y + halfH <= layout.canvasHeight - margin + 1e-9
    }
}

