import Foundation

public enum HitResult: Equatable, Sendable {
    case none
    case sector(id: String)
}

public struct HitTesting: Equatable, Sendable {
    public var layout: SemicircleLayout
    public var sectors: [ChartSector]

    public init(layout: SemicircleLayout = .selectedBase, sectors: [ChartSector]) {
        self.layout = layout
        self.sectors = sectors
    }

    /// Valid hit = visible crop ∩ canvas ∩ platter face ∩ mathematical semicircle ∩ unique half-open sector,
    /// minus eye, hub, and the origin point. Text is not part of the test (it must not block).
    /// Color sampling is not used. If there is no chartable sector list, nothing is hittable.
    public func hit(at point: Point2D) -> HitResult {
        if sectors.isEmpty { return .none }
        if !layout.isInsideCanvas(point) { return .none }
        if !layout.isInsideVisibleCrop(point) { return .none }
        if layout.isDecorativeExclusion(point) { return .none }
        if !layout.isInsideMathematicalSemicircle(point) { return .none }
        if !layout.isInsidePlatterFace(point) { return .none }

        let angle = layout.polarAngleDegrees(of: point)
        guard let sector = sector(containingAngle: angle) else { return .none }
        return .sector(id: sector.id)
    }

    /// True only for a valid disk-face sector hit. Eyes, hub, origin, crop exterior,
    /// decorative backplate, and transparent window regions are not the disc.
    /// 15:53: this gates sector INFO only; gaze uses independent window membership.
    public func isOnDisc(_ point: Point2D) -> Bool {
        if case .sector = hit(at: point) { return true }
        return false
    }

    /// Half-open [start, end) except the last sector, which includes 360°.
    public func sector(containingAngle angle: Double) -> ChartSector? {
        guard !sectors.isEmpty else { return nil }
        for (index, sector) in sectors.enumerated() {
            let isLast = index == sectors.count - 1
            if isLast {
                if angle >= sector.startDegrees && angle <= sector.endDegrees {
                    return sector
                }
            } else if angle >= sector.startDegrees && angle < sector.endDegrees {
                return sector
            }
        }
        return nil
    }

    public func sector(id: String) -> ChartSector? {
        sectors.first { $0.id == id }
    }
}
