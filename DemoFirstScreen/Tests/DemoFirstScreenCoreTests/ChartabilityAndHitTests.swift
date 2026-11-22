import XCTest
@testable import DemoFirstScreenCore

final class ChartabilityAndHitTests: XCTestCase {
    func testCompletenessAndOverlapGate() throws {
        let base = try TestSupport.chartableFixture()
        var unverified = base
        unverified.nonOverlapVerified = false
        if case .insufficient(let reason) = ChartabilityGate.evaluate(unverified) {
            XCTAssertTrue(reason.contains("不得图化"))
        } else {
            XCTFail("unverified overlap must not chart")
        }

        var noDedup = base
        noDedup.apfsRootDataDedupVerified = false
        XCTAssertFalse(ChartabilityGate.evaluate(noDedup).isChartable)

        var tooMany = base
        tooMany.items = base.items + [
            SnapshotItem(id: "X", name: "X", bytes: 1, errorCount: 0, readStatus: .reportedComplete),
            SnapshotItem(id: "Y", name: "Y", bytes: 1, errorCount: 0, readStatus: .reportedComplete)
        ]
        XCTAssertEqual(tooMany.items.count, 6)
        XCTAssertFalse(ChartabilityGate.evaluate(tooMany).isChartable)
    }

    func testSweepSumsTo180AndMatchesShares() throws {
        let session = try TestSupport.sessionFixture()
        guard case .chartable(let sectors, let denom) = session.chartability else {
            return XCTFail("fixture should be chartable")
        }
        XCTAssertEqual(denom, 200_000_000_000)
        XCTAssertEqual(sectors.count, 4)
        let sum = sectors.reduce(0.0) { $0 + $1.sweepDegrees }
        XCTAssertEqual(sum, 180.0, accuracy: 1e-9)
        XCTAssertEqual(sectors[0].id, "Users")
        XCTAssertEqual(sectors[0].sweepDegrees, 90, accuracy: 1e-9)
        XCTAssertEqual(sectors[1].sweepDegrees, 45, accuracy: 1e-9)
        XCTAssertEqual(sectors[2].sweepDegrees, 27, accuracy: 1e-9)
        XCTAssertEqual(sectors[3].sweepDegrees, 18, accuracy: 1e-9)
        XCTAssertEqual(sectors[0].startDegrees, 180, accuracy: 1e-9)
        XCTAssertEqual(sectors[sectors.count - 1].endDegrees, 360, accuracy: 1e-9)
    }

    func testBoundaryBelongsToExactlyOneSector() throws {
        let session = try TestSupport.sessionFixture()
        let hits = session.hits
        // 270° is the Users/System boundary: half-open so Users is [180,270), System is [270,315).
        let users = hits.sector(containingAngle: 269.999)!
        let at270 = hits.sector(containingAngle: 270)!
        let before = hits.sector(containingAngle: 180)!
        let at360 = hits.sector(containingAngle: 360)!
        XCTAssertEqual(users.id, "Users")
        XCTAssertEqual(at270.id, "System")
        XCTAssertEqual(before.id, "Users")
        XCTAssertEqual(at360.id, "Applications")
        XCTAssertNotEqual(users.id, at270.id)

        // Reconstruct a point at exactly 270° on the platter face and ensure a single hit.
        let layout = session.layout
        let rad = 270.0 * Double.pi / 180.0
        guard let maxR = layout.radiusToPlatterClip(atDegrees: 270) else {
            return XCTFail("270° must intersect the documented clip ellipse")
        }
        let r = maxR * 0.5
        let point = Point2D(x: layout.center.x + cos(rad) * r, y: layout.center.y + sin(rad) * r)
        XCTAssertEqual(hits.hit(at: point), .sector(id: "System"))
    }

    func testEyeHubOriginAndOutsideCropHaveNoHitAndDoNotPenetrate() throws {
        let session = try TestSupport.sessionFixture()
        let layout = session.layout
        let hits = session.hits

        // A Users-sector angle that lands inside the left eye must not hit.
        let eye = layout.eyeExclusions[0].center
        XCTAssertEqual(hits.hit(at: eye), .none)
        XCTAssertTrue(layout.isInsideEye(eye))

        XCTAssertEqual(hits.hit(at: layout.center), .none, "origin is excluded")
        let hubPoint = Point2D(x: layout.center.x, y: layout.center.y - 40)
        XCTAssertEqual(hits.hit(at: hubPoint), .none)

        let outside = Point2D(x: 10, y: 10)
        XCTAssertEqual(hits.hit(at: outside), .none)

        let outsideCrop = Point2D(x: -8, y: 1000)
        XCTAssertEqual(hits.hit(at: outsideCrop), .none)

        var cropped = layout
        cropped.sideCrop = SideCrop(left: 400, right: 400)
        let croppedHits = HitTesting(layout: cropped, sectors: session.chartability.sectors)
        let leftEdge = Point2D(x: 100, y: 1200)
        XCTAssertEqual(croppedHits.hit(at: leftEdge), .none, "hits outside a configured side crop are invalid")
        // Default remains no crop; this only checks the configurable path.
        XCTAssertTrue(SemicircleLayout.selectedBase.sideCrop.isPendingUnchangedDefault)
    }

    func testDefaultLayoutIsCompleteMathematicalSemicircleNotEllipse() {
        let layout = SemicircleLayout.selectedBase
        XCTAssertEqual(layout.center, Point2D(x: 1200, y: 1800))
        // selected-base-0353-frame02/geometry.json true_circle_radius_output
        XCTAssertEqual(layout.radius, 3000)
        XCTAssertEqual(layout.canvasWidth / layout.canvasHeight, 4.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(layout.sideCrop, .none, "no invented SideCrop ratio; canvas vs r=3000 is the documented crop")
        // Clip is the documented original platter ellipse; it is not the angle math.
        XCTAssertEqual(layout.platterClipEllipse.minX, -182)
        XCTAssertEqual(layout.platterClipEllipse.minY, 548)
        XCTAssertEqual(layout.platterClipEllipse.maxX, 2582)
        XCTAssertEqual(layout.platterClipEllipse.maxY, 2320)
        XCTAssertNotEqual(layout.platterClipEllipse.radiusX, layout.platterClipEllipse.radiusY)
        // Mathematical rim at 270° is above the canvas; display crop does not shrink the radius.
        let rim = Point2D(x: 1200, y: 1800 - 3000)
        XCTAssertTrue(layout.isInsideMathematicalSemicircle(rim))
        XCTAssertFalse(layout.isInsideCanvas(rim))
        XCTAssertFalse(layout.isInsideVisibleCrop(rim))
        XCTAssertFalse(layout.isInsidePlatterFace(rim))
    }

    func testPointerEnteringEyeClearsP() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: users))
        XCTAssertEqual(session.state.pointerPreviewID, "Users")
        session.pointerMoved(to: session.layout.eyeExclusions[0].center)
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.activeInput, .pointer)
    }

    func testServiceBoundaryListsOriginalServicesAndPackageDoesNotImportThem() {
        XCTAssertTrue(ServiceBoundary.forbiddenTypeNames.contains("DirectoryScanner"))
        XCTAssertTrue(ServiceBoundary.forbiddenTypeNames.contains("MonitorSession"))
        XCTAssertTrue(ServiceBoundary.forbiddenTypeNames.contains("MacFSEventsMonitor"))
    }

    func testBundledD2ArtworkIsTheDocumentedIconCrop() {
        for name in ["d2-hub", "d2-eyes-rest", "d2-eyes-gaze-left", "d2-eyes-gaze-right"] {
            XCTAssertNotNil(DemoArtwork.url(named: name), "missing \(name)")
        }
        XCTAssertEqual(SelectedBaseArtwork.hubOrigin, Point2D(x: 1000, y: 1664))
        XCTAssertEqual(SelectedBaseArtwork.hubSize, Point2D(x: 400, y: 354))
        XCTAssertEqual(SelectedBaseArtwork.eyesOrigin, Point2D(x: 546, y: 12))
        XCTAssertEqual(SelectedBaseArtwork.eyesSize, Point2D(x: 1308, y: 762))
    }
}
