import XCTest
import DemoFirstScreenCore

final class BackplateAndUncroppedEyeTests: XCTestCase {
    func testBoardIsStackedLipsNotFullCanvasWash() {
        XCTAssertTrue(CoralBackplate.contains(CoralBackplate.opaqueVisibleSampleLip))
        XCTAssertTrue(CoralBackplate.contains(CoralBackplate.opaqueVisibleSampleRight))
        XCTAssertTrue(CoralBackplate.lipContains(Point2D(x: 200, y: 450)))
        // Extra top wash (above lipMinY) is not part of the board.
        XCTAssertEqual(CoralBackplate.lipMinY, 348, accuracy: 1e-9)
        XCTAssertTrue(CoralBackplate.isAboveLips(CoralBackplate.aboveLipsTransparentSample))
        XCTAssertTrue(CoralBackplate.isAboveLips(CoralBackplate.aboveLipsTransparentSample2))
        XCTAssertFalse(CoralBackplate.contains(CoralBackplate.aboveLipsTransparentSample))
        XCTAssertFalse(CoralBackplate.contains(CoralBackplate.aboveLipsTransparentSample2))
        XCTAssertFalse(CoralBackplate.contains(Point2D(x: 1200, y: 80)))
        // Lips still form a wide enclosure, not a thin rim around the disc edge only.
        XCTAssertLessThan(CoralBackplate.lipMinY, 530)
        XCTAssertTrue(CoralBackplate.lipContains(Point2D(x: 80, y: 500)))
    }

    func testBothEyeContoursSitFullyInsideCanvasWithTopMargin() {
        let layout = SemicircleLayout.selectedBase
        XCTAssertEqual(layout.eyeExclusions.count, 2)
        let left = layout.eyeExclusions[0]
        let right = layout.eyeExclusions[1]
        let margin = EyePlacement.topSafetyMargin
        XCTAssertEqual(left.center, Point2D(x: 888, y: 378))
        XCTAssertEqual(right.center, Point2D(x: 1518, y: 432))
        XCTAssertEqual(left.minY, margin, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(right.minY, margin)
        XCTAssertGreaterThanOrEqual(left.minX, 0)
        XCTAssertLessThanOrEqual(right.maxX, layout.canvasWidth)
        XCTAssertGreaterThanOrEqual(SelectedBaseArtwork.eyesOrigin.y, 0)
        let span = EyePlacement.binocularSpan(layout: layout)
        XCTAssertEqual(span, 1272, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(span, 1270)
        XCTAssertLessThanOrEqual(span, 1277)
        // Eyes protrude above the lips into the now-transparent upper field.
        XCTAssertLessThan(left.minY, CoralBackplate.lipMinY)
        XCTAssertLessThan(right.minY, CoralBackplate.lipMinY)
    }

    func testHitGeometryTracksLiftedEyes() {
        let layout = SemicircleLayout.selectedBase
        let left = layout.eyeExclusions[0]
        XCTAssertTrue(layout.isInsideEye(Point2D(x: left.center.x, y: left.center.y)))
        XCTAssertFalse(layout.isInsideEye(Point2D(x: 888, y: 0)))
        XCTAssertEqual(VectorEyeSpec.left.shell.center, left.center)
        XCTAssertEqual(VectorEyeSpec.right.shell.center, layout.eyeExclusions[1].center)
    }
}

final class DefaultSectorLabelTests: XCTestCase {
    func testDefaultOpenExposesFiveCoreLabelsWithoutPointer() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let frame = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: true)
        XCTAssertNil(session.state.displayedID)
        XCTAssertTrue(frame.info.isOverview)
        XCTAssertFalse(frame.infoPlacement.isVisible)
        XCTAssertEqual(frame.sectorCoreLabels.count, 5)
        let ids = frame.sectorCoreLabels.map(\.id)
        XCTAssertEqual(ids, ["Movies", "Archives", "Documents", "Pictures", "Projects"])
        for label in frame.sectorCoreLabels {
            XCTAssertFalse(label.name.isEmpty)
            XCTAssertFalse(label.sizeText.isEmpty)
            XCTAssertFalse(label.sizeText.contains("示例"))
            XCTAssertGreaterThan(label.center.x, 0)
            XCTAssertLessThan(label.center.x, 2400)
            XCTAssertGreaterThan(label.center.y, 0)
            XCTAssertLessThan(label.center.y, 1800)
            // Core labels sit on the platter face, not in the removed top wash.
            XCTAssertGreaterThan(label.center.y, CoralBackplate.lipMinY)
            XCTAssertFalse(session.layout.isInsideEye(label.center))
            XCTAssertFalse(session.layout.isInsideHub(label.center))
        }
        XCTAssertEqual(frame.sectorCoreLabels[0].name, "影片")
        XCTAssertTrue(frame.sectorCoreLabels[0].sizeText.contains("72"))
    }

    func testHoverDoesNotDropTheOtherFourCoreLabels() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let movies = session.hits.sectors.first { $0.id == "Movies" }!
        let point = TestSupport.interiorPoint(of: movies, layout: session.layout)
        var moving = session
        moving.pointerMoved(to: point)
        let frame = FramePresentation.make(session: moving, motion: .reduced, pointerInsideWindow: true)
        XCTAssertEqual(frame.highlightID, "Movies")
        XCTAssertTrue(frame.infoPlacement.isVisible)
        XCTAssertEqual(frame.sectorCoreLabels.count, 5)
        XCTAssertEqual(Set(frame.sectorCoreLabels.map(\.id)).count, 5)
    }
}
