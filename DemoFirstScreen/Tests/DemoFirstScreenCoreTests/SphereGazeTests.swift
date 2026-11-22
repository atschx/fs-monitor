import XCTest
@testable import DemoFirstScreenCore

final class SphereGazeTests: XCTestCase {
    func testDefaultTargetIsLargestExampleSectorMoviesAndIsNotALock() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let target = SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout)
        XCTAssertEqual(SphereGaze.defaultTargetID(sectors: session.chartability.sectors), "Movies")
        XCTAssertEqual(session.hits.hit(at: target), HitResult.sector(id: "Movies"))

        let frame = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertFalse(frame.eye.followsPointer)
        XCTAssertEqual(frame.eye.defaultTargetID, "Movies")
        XCTAssertEqual(frame.eye.resolvedTarget, target)
        XCTAssertNil(session.state.lockedID)
        XCTAssertTrue(frame.info.isOverview)
        XCTAssertFalse(frame.infoPlacement.isVisible)
        XCTAssertEqual(frame.sectorCoreLabels.count, 5)
        XCTAssertEqual(frame.eye.leftShellCenter, Point2D(x: 888, y: 378))
        XCTAssertEqual(frame.eye.rightShellCenter, Point2D(x: 1518, y: 432))
        let span = EyePlacement.binocularSpan(layout: session.layout)
        XCTAssertEqual(span, 1272, accuracy: 1e-9)
    }

    func testBothEyesConvergeOnTheSameTargetAndForeshortenWhenLookingAside() throws {
        let leftNear = SphereGaze.pose(spec: .left, target: Point2D(x: 500, y: 1100))
        let rightNear = SphereGaze.pose(spec: .right, target: Point2D(x: 500, y: 1100))
        XCTAssertNotEqual(leftNear.direction, rightNear.direction)
        XCTAssertEqual(leftNear.shellCenter, VectorEyeSpec.left.shell.center)
        XCTAssertEqual(rightNear.shellCenter, VectorEyeSpec.right.shell.center)

        let leftFar = SphereGaze.pose(spec: .left, target: Point2D(x: 2000, y: 1400))
        // Far-right aim from the left globe should show more foreshortening than a nearer aim.
        XCTAssertLessThan(leftFar.facing, leftNear.facing)
        XCTAssertGreaterThan(leftFar.facing, 0)
        XCTAssertLessThanOrEqual(acos(min(1, max(-1, leftFar.facing))), SphereGaze.maxPolarAngle + 1e-9)
        XCTAssertNotEqual(leftNear.projectedIrisCenter, leftFar.projectedIrisCenter)
    }

    func testLockOnProjectsDoesNotStealDefaultGazeOffDisc() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let projects = session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        session.pointerClicked(at: projects)
        XCTAssertEqual(session.state.lockedID, "Projects")
        let following = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertTrue(following.eye.followsPointer)
        XCTAssertEqual(following.info.id, "Projects")

        session.pointerExitedVisibleArea()
        let away = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertEqual(session.state.lockedID, "Projects")
        XCTAssertEqual(away.info.id, "Projects")
        XCTAssertFalse(away.eye.followsPointer)
        XCTAssertEqual(away.eye.defaultTargetID, "Movies")
        XCTAssertEqual(away.eye.resolvedTarget, away.eye.defaultTarget)
        XCTAssertNotEqual(away.eye.resolvedTarget, following.eye.resolvedTarget)
        XCTAssertEqual(away.sectorCoreLabels.count, 5)
    }

    func testContactShadowIsPerEyeAndNotTheWideResidualOval() {
        let left = SphereGaze.contactShadow(spec: .left)
        let right = SphereGaze.contactShadow(spec: .right)
        let residual = AxisAlignedEllipse(
            center: Point2D(
                x: (SelectedBaseArtwork.eyeShadowMin.x + SelectedBaseArtwork.eyeShadowMax.x) / 2,
                y: (SelectedBaseArtwork.eyeShadowMin.y + SelectedBaseArtwork.eyeShadowMax.y) / 2
            ),
            radiusX: (SelectedBaseArtwork.eyeShadowMax.x - SelectedBaseArtwork.eyeShadowMin.x) / 2,
            radiusY: (SelectedBaseArtwork.eyeShadowMax.y - SelectedBaseArtwork.eyeShadowMin.y) / 2
        )
        XCTAssertLessThan(left.radiusX, residual.radiusX)
        XCTAssertLessThan(right.radiusX, residual.radiusX)
        XCTAssertLessThan(left.maxX, right.minX, "contact shadows are two tight ovals, not one spanning stain")
        XCTAssertEqual(left.center.x, VectorEyeSpec.left.shell.center.x, accuracy: 1e-9)
        XCTAssertEqual(right.center.x, VectorEyeSpec.right.shell.center.x, accuracy: 1e-9)
    }

    func testIrisCapIsOnTheSphereAndHighlightFollowsTheNormal() {
        let pose = SphereGaze.pose(spec: .left, target: Point2D(x: 400, y: 1300))
        let dir = pose.direction
        // A surface point along the gaze axis (front cap center) must be iris/pupil.
        let alongX = dir.x * 0.35
        let alongY = dir.y * 0.35
        XCTAssertTrue(SphereShade.isOnGlobe(unitX: alongX, unitY: alongY))
        XCTAssertTrue(SphereShade.isInIrisCap(unitX: alongX, unitY: alongY, dir: dir, irisAlpha: pose.irisAngularRadius))
        // The opposite limb of the visible globe is sclera, not a floating iris disc.
        let awayX = -dir.x * 0.72
        let awayY = -dir.y * 0.72
        XCTAssertTrue(SphereShade.isOnGlobe(unitX: awayX, unitY: awayY))
        XCTAssertFalse(SphereShade.isInIrisCap(unitX: awayX, unitY: awayY, dir: dir, irisAlpha: pose.irisAngularRadius))

        // Blinn-Phong peak is where the normal equals the half-vector, not
        // the screen centre of the sclera (the 073448 floating disc).
        let half = (SphereShade.light + SphereShade.view).normalized()
        XCTAssertGreaterThan(half.z, 0)
        let peak = SphereShade.specularAlignment(unitX: half.x, unitY: half.y)
        let atPole = SphereShade.specularAlignment(unitX: 0, unitY: 0)
        XCTAssertGreaterThan(peak, atPole)
        XCTAssertGreaterThan(peak, 0.99)
    }

    func testOnDiscSectorsDoNotShareASingleForeshorten() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let angles = [200.0, 252.0, 297.0, 328.0, 351.0]
        var facings: [Double] = []
        for deg in angles {
            session.pointerMoved(to: session.layout.pointOnRay(degrees: deg, radiusFraction: 0.55))
            let frame = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
            XCTAssertTrue(frame.eye.followsPointer)
            facings.append(frame.eye.leftPose.facing)
            XCTAssertGreaterThan(frame.eye.leftPose.facing, 0)
            XCTAssertLessThanOrEqual(acos(min(1, max(-1, frame.eye.leftPose.facing))), SphereGaze.maxSafePolarAngle + 1e-9)
        }
        XCTAssertGreaterThan(Set(facings.map { ($0 * 1000).rounded() }).count, 1, "facing must vary across the disc; a 48° hard clamp is not allowed")
    }
}
