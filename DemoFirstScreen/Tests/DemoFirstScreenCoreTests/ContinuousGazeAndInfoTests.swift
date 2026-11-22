import XCTest
@testable import DemoFirstScreenCore

final class ContinuousGazeAndInfoTests: XCTestCase {
    func testSameSectorDifferentPointsProduceDifferentOffsets() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let a = session.layout.pointOnRay(degrees: 190, radiusFraction: 0.50)
        let b = session.layout.pointOnRay(degrees: 220, radiusFraction: 0.58)
        XCTAssertEqual(session.hits.hit(at: a), HitResult.sector(id: "Movies"))
        XCTAssertEqual(session.hits.hit(at: b), HitResult.sector(id: "Movies"))

        session.pointerMoved(to: a)
        let genA = session.state.generation
        let frameA = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        session.pointerMoved(to: b)
        let frameB = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)

        XCTAssertEqual(session.state.displayedID, "Movies")
        XCTAssertEqual(session.state.generation, genA, "same-sector pointer moves must not bump display identity")
        XCTAssertTrue(frameA.eye.followsPointer)
        XCTAssertTrue(frameB.eye.followsPointer)
        XCTAssertNotEqual(frameA.eye.leftPose.direction, frameB.eye.leftPose.direction)
        XCTAssertNotEqual(frameA.eye.rightPose.direction, frameB.eye.rightPose.direction)
        XCTAssertNotEqual(frameA.eye.leftPupilOffset, frameB.eye.leftPupilOffset)
        XCTAssertNotEqual(frameA.eye.rightPupilOffset, frameB.eye.rightPupilOffset)
        XCTAssertEqual(frameA.infoPlacement.center, frameB.infoPlacement.center, "info anchor stays stable inside one sector")
        XCTAssertEqual(frameA.eye.leftShellCenter, Point2D(x: 888, y: 378))
        XCTAssertEqual(frameA.eye.rightShellCenter, Point2D(x: 1518, y: 432))
        XCTAssertEqual(frameA.eye.leftShellCenter, frameB.eye.leftShellCenter)
        XCTAssertEqual(frameA.eye.rightShellCenter, frameB.eye.rightShellCenter)
        XCTAssertEqual(frameA.sectorCoreLabels.count, 5)
    }

    func testCrossSectorDirectionsChangeAndShellsStayPut() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let maxAngle = SphereGaze.maxPolarAngle + 1e-9
        // Mid-ish angle of each of the five example sectors (54/45/36/27/18).
        let points = [200.0, 252.0, 297.0, 328.0, 351.0].map {
            session.layout.pointOnRay(degrees: $0, radiusFraction: 0.55)
        }
        var previous: Vec3?
        var ids: [String] = []
        for point in points {
            session.pointerMoved(to: point)
            let frame = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
            XCTAssertTrue(frame.eye.followsPointer)
            XCTAssertEqual(frame.eye.leftShellCenter, Point2D(x: 888, y: 378))
            let polar = acos(min(1, max(-1, frame.eye.leftPose.facing)))
            XCTAssertLessThanOrEqual(polar, maxAngle)
            XCTAssertGreaterThan(frame.eye.leftPose.facing, 0)
            if let previous {
                XCTAssertNotEqual(frame.eye.leftPose.direction, previous)
            }
            previous = frame.eye.leftPose.direction
            if let id = frame.highlightID { ids.append(id) }
        }
        XCTAssertEqual(Set(ids).count, 5, "cross-sector path should visit all five example sectors")
    }

    func testLeavingWindowReturnsNeutralAndDoesNotTrackOutside() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let point = session.layout.pointOnRay(degrees: 200, radiusFraction: 0.55)
        session.pointerMoved(to: point)
        let inside = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertTrue(inside.eye.followsPointer)
        XCTAssertNotNil(session.state.pointerLocation)

        session.pointerExitedVisibleArea()
        let outside = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: false)
        let idle = FramePresentation.make(
            session: InteractionSession(snapshot: session.snapshot),
            motion: .defaultMotion,
            pointerInsideWindow: true
        )
        XCTAssertNil(session.state.pointerLocation)
        XCTAssertFalse(outside.eye.followsPointer)
        XCTAssertEqual(outside.eye.resolvedTarget, idle.eye.defaultTarget)
        XCTAssertEqual(outside.eye.defaultTargetID, "Movies")
        XCTAssertEqual(outside.eye.leftPose.direction, idle.eye.leftPose.direction)
        XCTAssertEqual(outside.eye.rightPose.direction, idle.eye.rightPose.direction)
        // Even if a caller passes pointerInsideWindow true with a cleared location, eyes stay at default.
        let ignored = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertFalse(ignored.eye.followsPointer)
        XCTAssertEqual(ignored.eye.leftPose.direction, idle.eye.leftPose.direction)
    }

    func testReduceMotionStillHasContinuousTargetWithZeroDuration() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let a = session.layout.pointOnRay(degrees: 190, radiusFraction: 0.5)
        let b = session.layout.pointOnRay(degrees: 220, radiusFraction: 0.5)
        session.pointerMoved(to: a)
        let fa = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: true)
        session.pointerMoved(to: b)
        let fb = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: true)
        XCTAssertEqual(fa.motion.gazeDurationMs, 0)
        XCTAssertFalse(fa.motion.allowsInterpolation)
        XCTAssertTrue(fa.eye.followsPointer)
        XCTAssertNotEqual(fa.eye.leftPose.direction, fb.eye.leftPose.direction)
    }

    func testLockDoesNotChangeActualObservationRange() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let before = session.state.actualObservationID
        let point = session.layout.pointOnRay(degrees: 200, radiusFraction: 0.55)
        session.pointerMoved(to: point)
        session.pointerClicked(at: point)
        XCTAssertEqual(session.state.lockedID, "Movies")
        XCTAssertEqual(session.state.actualObservationID, before)
        let later = session.layout.pointOnRay(degrees: 300, radiusFraction: 0.55)
        session.pointerMoved(to: later)
        XCTAssertEqual(session.state.actualObservationID, before)
    }

    func testInfoAnchorFollowsSectorSideAndCollapsesWithoutLock() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let movies = session.hits.sector(id: "Movies")!
        let projects = session.hits.sector(id: "Projects")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: movies, layout: session.layout))
        let left = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        session.pointerMoved(to: TestSupport.interiorPoint(of: projects, layout: session.layout))
        let right = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)

        XCTAssertTrue(left.infoPlacement.isVisible)
        XCTAssertTrue(right.infoPlacement.isVisible)
        XCTAssertLessThan(left.infoPlacement.center.x, right.infoPlacement.center.x)
        XCTAssertNotEqual(left.infoPlacement.center, right.infoPlacement.center)
        XCTAssertTrue(left.infoPlacement.isClamped(to: session.layout))
        XCTAssertTrue(right.infoPlacement.isClamped(to: session.layout))
        XCTAssertNotEqual(left.infoPlacement.center, Point2D(x: 400, y: 1100), "must not keep the old fixed first-sector-left anchor")

        session.pointerExitedVisibleArea()
        let afterLeaveNoLock = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertFalse(afterLeaveNoLock.infoPlacement.isVisible)
        XCTAssertTrue(afterLeaveNoLock.info.isOverview)

        session.pointerClicked(at: TestSupport.interiorPoint(of: projects, layout: session.layout))
        session.pointerExitedVisibleArea()
        let afterLeaveLocked = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertEqual(session.state.lockedID, "Projects")
        XCTAssertTrue(afterLeaveLocked.infoPlacement.isVisible)
        XCTAssertEqual(afterLeaveLocked.infoPlacement.identityID, "Projects")
        XCTAssertEqual(afterLeaveLocked.infoPlacement.center, right.infoPlacement.center)
        XCTAssertEqual(afterLeaveLocked.info.id, "Projects")
    }

    func testVectorShellIsFixedUnderSphericalPose() {
        let spec = VectorEyeSpec.left
        XCTAssertEqual(spec.shell.center, Point2D(x: 888, y: 378))
        let a = SphereGaze.pose(spec: spec, target: Point2D(x: 400, y: 1200))
        let b = SphereGaze.pose(spec: spec, target: Point2D(x: 2000, y: 1400))
        XCTAssertEqual(a.shellCenter, spec.shell.center)
        XCTAssertEqual(b.shellCenter, spec.shell.center)
        XCTAssertNotEqual(a.direction, b.direction)
        XCTAssertEqual(spec.shell.center, Point2D(x: 888, y: 378), "shell must not travel with the iris")
    }

    func testHitOnEyeClearsPreviewButKeepsWindowGaze() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let movies = TestSupport.interiorPoint(of: session.hits.sector(id: "Movies")!, layout: session.layout)
        session.pointerClicked(at: movies)
        XCTAssertEqual(session.state.lockedID, "Movies")
        XCTAssertEqual(session.state.pointerPreviewID, "Movies")

        let eyePoint = VectorEyeSpec.left.shell.center
        XCTAssertTrue(session.layout.isInsideEye(eyePoint))
        XCTAssertFalse(session.hits.isOnDisc(eyePoint), "eyes are not the disc")
        session.pointerMoved(to: eyePoint)
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.lockedID, "Movies")
        let frame = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertEqual(frame.info.id, "Movies", "L still restores info")
        XCTAssertTrue(frame.eye.followsPointer, "15:53: eyes follow the local point, not L or disc-only")
        XCTAssertEqual(frame.eye.defaultTargetID, "Movies")
        XCTAssertEqual(frame.eye.resolvedTarget, eyePoint)
        let idle = FramePresentation.make(
            session: InteractionSession(snapshot: session.snapshot),
            motion: .defaultMotion,
            pointerInsideWindow: true
        )
        XCTAssertNotEqual(frame.eye.leftPose.direction, idle.eye.leftPose.direction)
        XCTAssertEqual(frame.sectorCoreLabels.count, 5)
    }
}
