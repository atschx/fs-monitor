import XCTest
@testable import DemoFirstScreenCore

final class ReduceMotionTests: XCTestCase {
    func testReduceMotionDurationsAreZeroAndInterpolationIsOff() {
        let reduced = MotionPolicy.reduced
        XCTAssertEqual(reduced.colorDurationMs, 0)
        XCTAssertEqual(reduced.gazeDurationMs, 0)
        XCTAssertEqual(reduced.infoDurationMs, 0)
        XCTAssertEqual(reduced.visualFallbackDurationMs, 0)
        XCTAssertFalse(reduced.allowsInterpolation)

        let normal = MotionPolicy.defaultMotion
        XCTAssertEqual(normal.colorDurationMs, 140)
        XCTAssertEqual(normal.gazeDurationMs, 240)
        XCTAssertEqual(normal.infoDurationMs, 160)
        XCTAssertEqual(normal.visualFallbackDurationMs, 0, "first version reverts visually immediately")
    }

    func testSphericalPoseKeepsShellsFixedAndStaysOnTheFrontHemisphere() throws {
        let session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        // A ray other than visibleInteriorPoint so this is not the default target.
        let target = session.layout.pointOnRay(degrees: (users.startDegrees + users.endDegrees) / 2, radiusFraction: 0.45)
        let defaultTarget = SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout)
        let eye = EyePresentation.make(
            layout: session.layout,
            target: target,
            followsPointer: true,
            defaultTarget: defaultTarget,
            defaultTargetID: SphereGaze.defaultTargetID(sectors: session.chartability.sectors)
        )
        XCTAssertEqual(eye.leftShellCenter, Point2D(x: 888, y: 378))
        XCTAssertEqual(eye.rightShellCenter, Point2D(x: 1518, y: 432))
        XCTAssertLessThanOrEqual(acos(min(1, max(-1, eye.leftPose.facing))), SphereGaze.maxPolarAngle + 1e-9)
        XCTAssertLessThanOrEqual(acos(min(1, max(-1, eye.rightPose.facing))), SphereGaze.maxPolarAngle + 1e-9)
        XCTAssertGreaterThan(eye.leftPose.facing, 0)
        XCTAssertNotEqual(eye.leftPose.direction, eye.rightPose.direction, "eyes converge on one target, so directions differ")
    }

    func testReduceMotionPresentationJumpsGazeAndInfoTogether() throws {
        var session = try TestSupport.sessionFixture()
        let motion = MotionPolicy.reduced
        let rest = FramePresentation.make(session: session, motion: motion, pointerInsideWindow: true)
        XCTAssertNil(rest.highlightID)
        XCTAssertFalse(rest.eye.followsPointer)
        XCTAssertEqual(rest.motion.gazeDurationMs, 0)

        let users = session.hits.sector(id: "Users")!
        // Avoid the exact default interior point (Users is largest in this fixture).
        let aim = session.layout.pointOnRay(degrees: users.startDegrees + 4, radiusFraction: 0.45)
        session.pointerMoved(to: aim)
        let next = FramePresentation.make(session: session, motion: motion, pointerInsideWindow: true)
        XCTAssertEqual(next.info.id, "Users")
        XCTAssertEqual(next.highlightID, "Users")
        XCTAssertEqual(next.motion.colorDurationMs, 0)
        XCTAssertTrue(next.eye.followsPointer)
        XCTAssertNotEqual(next.eye.leftPose.direction, rest.eye.leftPose.direction)
        XCTAssertEqual(next.generation, session.state.generation)
    }

    func testEyeDoesNotTrackWhenPointerLeavesTheWindow() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        session.pointerMoved(to: session.layout.pointOnRay(degrees: users.startDegrees + 4, radiusFraction: 0.45))
        let inside = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        session.pointerExitedVisibleArea()
        let outside = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertFalse(outside.eye.followsPointer)
        XCTAssertTrue(inside.eye.followsPointer)
        XCTAssertEqual(outside.eye.resolvedTarget, outside.eye.defaultTarget)
        XCTAssertNotEqual(inside.eye.leftPose.direction, outside.eye.leftPose.direction)
        XCTAssertEqual(outside.info.id, session.state.displayedID)
    }
}
