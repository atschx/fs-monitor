import Foundation
@testable import DemoFirstScreenCore
import XCTest

enum TestSupport {
    static let layout = SemicircleLayout.selectedBase

    static func dates() -> (Date, Date) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        let a = f.date(from: "2026-11-21T00:00:00-08:00")!
        let b = f.date(from: "2026-11-21T00:00:01-08:00")!
        return (a, b)
    }

    static func chartableFixture() throws -> DemoSnapshot {
        let url = Bundle.module.url(forResource: "chartable-four-sectors-testOnly.json", withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "chartable-four-sectors-testOnly", withExtension: "json")
        guard let url else { throw SnapshotLoadError.resourceMissing("chartable-four-sectors-testOnly.json") }
        let snapshot = try SnapshotLoader.decode(Data(contentsOf: url))
        XCTAssertTrue(snapshot.testOnly)
        return snapshot
    }

    static func productionSnapshot() throws -> DemoSnapshot {
        try SnapshotLoader.loadBundledProduction()
    }

    /// A point clearly inside a sector on the platter face, away from eyes, hub, and origin.
    static func interiorPoint(of sector: ChartSector, layout: SemicircleLayout = layout) -> Point2D {
        layout.visibleInteriorPoint(startDegrees: sector.startDegrees, endDegrees: sector.endDegrees)
    }

    static func sessionFixture() throws -> InteractionSession {
        InteractionSession(snapshot: try chartableFixture(), layout: layout)
    }
}
