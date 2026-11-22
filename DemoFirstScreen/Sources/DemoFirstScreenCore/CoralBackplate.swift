import Foundation

/// Solid coral board behind the disc: stacked rounded lips (2× draw_review.py
/// L18–21). This is a spatial anchor behind and beside the platter, not a
/// thin rim strip, and not a full-window coral wash.
///
/// Albert 06:43 feedback (shared still
/// `Albert-feedback-extra-top-background-empty-disc-0643.png`) asked to remove
/// the extra full-width wash from the top of the frame down to the upper
/// edge of the stacked lips, while keeping the lips and the board behind
/// and below them to the disc edge. The design cut is `lipMinY` (348),
/// which is 2× of draw_review.py’s shallowest lip (y=174 on the 1200 canvas).
/// A 1024×768 viewing of that still has the lip near y≈147; that screenshot
/// row is only a locator, not a geometry constant.
///
/// The region above `lipMinY` (behind the protruding eyes, top of the
/// window) is left undrawn so the transparent window shows through. This
/// type does not punch holes in the lips themselves.
public enum CoralBackplate: Equatable, Sendable {
    public struct Layer: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double
        public var corner: Double
        public var fillHex: String
        public var strokeHex: String?
        public var lineWidth: Double
    }

    /// Stacked rounded lips, 2× of draw_review.py L18–21.
    public static let layers: [Layer] = [
        Layer(minX: -124, minY: 380, maxX: 2524, maxY: 2100, corner: 250, fillHex: Palette.shellOuterDeep, strokeHex: nil, lineWidth: 0),
        Layer(minX: -116, minY: 348, maxX: 2516, maxY: 2060, corner: 250, fillHex: Palette.shellOuterMid, strokeHex: Palette.shellOuterMidStroke, lineWidth: 10),
        Layer(minX: -66, minY: 414, maxX: 2466, maxY: 2060, corner: 218, fillHex: Palette.shellInnerDeep, strokeHex: Palette.shellInnerDeepStroke, lineWidth: 10),
        Layer(minX: -20, minY: 458, maxX: 2420, maxY: 2020, corner: 188, fillHex: Palette.shellInnerLight, strokeHex: Palette.shellInnerLightStroke, lineWidth: 8)
    ]

    /// Upper edge of the stacked lips on the 2400×1800 canvas. The extra
    /// top wash (y < this) is not part of the board.
    public static var lipMinY: Double { layers.map(\.minY).min() ?? 348 }

    /// Visible coral on the left lip band, left of the eyes, below lipMinY
    /// and above the platter rim at this x.
    public static let opaqueVisibleSampleLip = Point2D(x: 200, y: 450)
    public static let opaqueVisibleSampleRight = Point2D(x: 2200, y: 450)

    /// Above the lips: intended transparent window background after 06:43.
    public static let aboveLipsTransparentSample = Point2D(x: 80, y: 80)
    public static let aboveLipsTransparentSample2 = Point2D(x: 200, y: 200)

    public static func roundedRectContains(
        _ point: Point2D,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        corner: Double
    ) -> Bool {
        if point.x < minX || point.x > maxX || point.y < minY || point.y > maxY {
            return false
        }
        let r = min(corner, (maxX - minX) / 2, (maxY - minY) / 2)
        let innerMinX = minX + r
        let innerMaxX = maxX - r
        let innerMinY = minY + r
        let innerMaxY = maxY - r
        if point.x >= innerMinX && point.x <= innerMaxX { return true }
        if point.y >= innerMinY && point.y <= innerMaxY { return true }
        let cx = point.x < innerMinX ? innerMinX : innerMaxX
        let cy = point.y < innerMinY ? innerMinY : innerMaxY
        let dx = point.x - cx
        let dy = point.y - cy
        return dx * dx + dy * dy <= r * r
    }

    public static func lipContains(_ point: Point2D) -> Bool {
        layers.contains { layer in
            roundedRectContains(
                point,
                minX: layer.minX,
                minY: layer.minY,
                maxX: layer.maxX,
                maxY: layer.maxY,
                corner: layer.corner
            )
        }
    }

    /// The board is the stacked lips only. The former full-canvas wash is
    /// not included.
    public static func contains(_ point: Point2D) -> Bool {
        lipContains(point)
    }

    public static func isAboveLips(_ point: Point2D) -> Bool {
        point.y < lipMinY
    }
}

/// Vertical lift of the documented D2 eye placement so both full globes stay
/// inside the 2400×1800 frame. Radii and binocular span are unchanged
/// (span 1272 / visible disc width 2400 ≈ 53%).
public enum EyePlacement: Equatable, Sendable {
    /// Left globe top was y=−32; this lift puts it at y=24.
    public static let canvasLift: Double = 56
    public static let topSafetyMargin: Double = 24

    public static func lifted(_ point: Point2D) -> Point2D {
        Point2D(x: point.x, y: point.y + canvasLift)
    }

    public static func lifted(_ ellipse: AxisAlignedEllipse) -> AxisAlignedEllipse {
        AxisAlignedEllipse(
            center: lifted(ellipse.center),
            radiusX: ellipse.radiusX,
            radiusY: ellipse.radiusY
        )
    }

    /// Distance from the left exclusion minX to the right exclusion maxX.
    public static func binocularSpan(layout: SemicircleLayout = .selectedBase) -> Double {
        guard layout.eyeExclusions.count >= 2 else { return 0 }
        let left = layout.eyeExclusions[0]
        let right = layout.eyeExclusions[1]
        return right.maxX - left.minX
    }
}

/// Default-open core label for one chartable sector. These are always
/// presented on a chartable snapshot so the disc is not empty. They are
/// not the hover/lock detail card, and they are not a visible example badge.
public struct SectorCoreLabel: Equatable, Sendable {
    public var id: String
    public var name: String
    public var sizeText: String
    public var center: Point2D

    public static let compactBoxWidth: Double = 300
    public static let compactBoxHeight: Double = 150
    public static let compactMargin: Double = 48

    public static func all(sectors: [ChartSector], layout: SemicircleLayout) -> [SectorCoreLabel] {
        sectors.map { sector in
            SectorCoreLabel(
                id: sector.id,
                name: sector.name,
                sizeText: DemoCopy.formatBytes(sector.bytes),
                center: compactCenter(for: sector, layout: layout)
            )
        }
    }

    public static func compactCenter(for sector: ChartSector, layout: SemicircleLayout) -> Point2D {
        var p = layout.visibleInteriorPoint(startDegrees: sector.startDegrees, endDegrees: sector.endDegrees)
        let halfW = compactBoxWidth / 2
        let halfH = compactBoxHeight / 2
        let margin = compactMargin
        p.x = min(max(p.x, margin + halfW), layout.canvasWidth - margin - halfW)
        p.y = min(max(p.y, margin + halfH), layout.canvasHeight - margin - halfH)
        if layout.isInsideEye(p) {
            p.y = min(p.y + 180, layout.canvasHeight - margin - halfH)
        }
        if layout.isInsideHub(p) {
            p.y = min(layout.center.y - layout.hubRadius - halfH - 16, layout.canvasHeight - margin - halfH)
        }
        return p
    }
}
