import XCTest
@testable import DemoFirstScreenCore

/// End-to-end on the top-down raster buffer (the same pixels SphereEyeRaster
/// wraps). 074605's cacheDisplay PNGs had the iris above the sclera while every
/// platter target was below; these tests fail that row-convention bug.
final class SphereRasterTests: XCTestCase {
    func testDefaultMoviesIrisIsBelowTheGlobeOnTheRaster() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let target = SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout)
        XCTAssertEqual(SphereGaze.defaultTargetID(sectors: session.chartability.sectors), "Movies")
        XCTAssertGreaterThan(target.y, VectorEyeSpec.left.sclera.center.y)
        XCTAssertGreaterThan(target.y, VectorEyeSpec.right.sclera.center.y)
        XCTAssertLessThan(target.x, VectorEyeSpec.left.sclera.center.x)

        for spec in [VectorEyeSpec.left, VectorEyeSpec.right] {
            let pose = SphereGaze.pose(spec: spec, target: target)
            XCTAssertGreaterThan(pose.direction.y, 0, "canvas +Y is down; Movies is below the globe")
            XCTAssertLessThan(pose.direction.x, 0)
            let buf = SphereRasterBuffer.render(spec: spec, pose: pose)
            let m = try XCTUnwrap(
                SphereImageMeasure.darkIrisCentroid(buffer: buf, sclera: spec.sclera),
                "expected a measurable iris on \(spec.shell.center)"
            )
            XCTAssertGreaterThan(m.unitY, 0.08, "target below ⇒ raster iris below sclera center, got unitY=\(m.unitY)")
            XCTAssertLessThan(m.unitX, -0.08, "Movies is to the left, got unitX=\(m.unitX)")
            XCTAssertTrue(SphereImageMeasure.sameDirection(m.unitY, target.y - spec.sclera.center.y))
            XCTAssertTrue(SphereImageMeasure.sameDirection(m.unitX, target.x - spec.sclera.center.x))
        }
    }

    func testProjectsIrisIsBelowAndToTheRightOnTheRaster() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let target = session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        XCTAssertGreaterThan(target.y, VectorEyeSpec.left.sclera.center.y)
        XCTAssertGreaterThan(target.x, VectorEyeSpec.left.sclera.center.x)

        var units: [(Double, Double)] = []
        for spec in [VectorEyeSpec.left, VectorEyeSpec.right] {
            let pose = SphereGaze.pose(spec: spec, target: target)
            let buf = SphereRasterBuffer.render(spec: spec, pose: pose)
            let m = try XCTUnwrap(SphereImageMeasure.darkIrisCentroid(buffer: buf, sclera: spec.sclera))
            XCTAssertGreaterThan(m.unitY, 0.08, "projects is below, got unitY=\(m.unitY)")
            XCTAssertTrue(SphereImageMeasure.sameDirection(m.unitX, target.x - spec.sclera.center.x))
            units.append((m.unitX, m.unitY))
        }
        // Both globes look at the same lower-right target; signs agree.
        XCTAssertGreaterThan(units[0].0, 0)
        XCTAssertGreaterThan(units[1].0, 0)
        XCTAssertGreaterThan(units[0].1, 0)
        XCTAssertGreaterThan(units[1].1, 0)
    }

    func testInvertedRowOrderWouldPlaceTheIrisAboveAndIsRejected() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let target = SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout)
        let spec = VectorEyeSpec.left
        let pose = SphereGaze.pose(spec: spec, target: target)
        let buf = SphereRasterBuffer.render(spec: spec, pose: pose)
        var flipped = buf
        let row = buf.bytesPerRow
        var rgba = buf.rgba
        for r in 0..<(buf.height / 2) {
            let a = r * row
            let b = (buf.height - 1 - r) * row
            for k in 0..<row {
                let tmp = rgba[a + k]
                rgba[a + k] = rgba[b + k]
                rgba[b + k] = tmp
            }
        }
        flipped.rgba = rgba
        let wrong = try XCTUnwrap(SphereImageMeasure.darkIrisCentroid(buffer: flipped, sclera: spec.sclera))
        XCTAssertLessThan(wrong.unitY, -0.08, "the 074605 row inversion must measure as ABOVE")
        let right = try XCTUnwrap(SphereImageMeasure.darkIrisCentroid(buffer: buf, sclera: spec.sclera))
        XCTAssertGreaterThan(right.unitY, 0.08)
        XCTAssertFalse(SphereImageMeasure.sameDirection(wrong.unitY, target.y - spec.sclera.center.y))
    }

    func testShellCentersStayAtTheDocumentedPlacement() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let targets = [
            SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout),
            session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        ]
        for target in targets {
            for spec in [VectorEyeSpec.left, VectorEyeSpec.right] {
                let pose = SphereGaze.pose(spec: spec, target: target)
                XCTAssertEqual(pose.shellCenter, spec.shell.center)
                XCTAssertEqual(pose.scleraCenter, spec.sclera.center)
            }
        }
        session.pointerMoved(to: Point2D(x: 80, y: 80))
        let away = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertTrue(away.eye.followsPointer)
        XCTAssertEqual(away.eye.defaultTargetID, "Movies")
        XCTAssertEqual(away.eye.resolvedTarget, Point2D(x: 80, y: 80))
        XCTAssertEqual(away.eye.leftShellCenter, Point2D(x: 888, y: 378))
        XCTAssertEqual(away.eye.rightShellCenter, Point2D(x: 1518, y: 432))
        let idle = FramePresentation.make(
            session: InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction()),
            motion: .defaultMotion,
            pointerInsideWindow: true
        )
        XCTAssertNotEqual(away.eye.leftPose.direction, idle.eye.leftPose.direction)
        XCTAssertNotEqual(away.eye.rightPose.direction, idle.eye.rightPose.direction)
    }
}
