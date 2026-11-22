import XCTest
@testable import DemoFirstScreenCore

final class WindowMotionAndCardTests: XCTestCase {
    func testLetterboxIsWindowInputButArtworkRatioAndPlacementStayFixed() {
        let native = WindowCanvasMap(width: 1200, height: 900)
        XCTAssertEqual(native.scale, 0.5)
        XCTAssertEqual(native.origin, Point2D(x: 0, y: 0))
        XCTAssertEqual(native.canvasPoint(Point2D(x: 444, y: 189)), VectorEyeSpec.left.shell.center)
        let wide = WindowCanvasMap(width: 1600, height: 900)
        XCTAssertEqual(wide.origin, Point2D(x: 200, y: 0))
        XCTAssertTrue(wide.contains(Point2D(x: 20, y: 450)))
        XCTAssertEqual(wide.canvasPoint(Point2D(x: 20, y: 450)), Point2D(x: -360, y: 900))
        XCTAssertEqual(wide.canvasPoint(Point2D(x: 644, y: 189)), VectorEyeSpec.left.shell.center)
        XCTAssertFalse(wide.contains(Point2D(x: 1600, y: 450)))
        let tall = WindowCanvasMap(width: 1200, height: 1200)
        XCTAssertEqual(tall.origin, Point2D(x: 0, y: 150))
        XCTAssertEqual(tall.canvasPoint(Point2D(x: 600, y: 20)), Point2D(x: 1200, y: -260))
        XCTAssertEqual(CoralBackplate.lipMinY, 348)
        XCTAssertEqual(VectorEyeSpec.right.shell.center, Point2D(x: 1518, y: 432))
    }
    func testOneTextIdentityForHoverLockKeyboardAndExit() throws {
        var s = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        func check(_ s: InteractionSession) {
            let f = FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: s.state.pointerLocation != nil)
            var visible = f.visibleSectorCoreLabels.map(\.id)
            if f.infoPlacement.isVisible, !f.info.isOverview, let id = f.infoPlacement.identityID { visible.append(id) }
            XCTAssertEqual(visible.count, 5)
            XCTAssertEqual(Set(visible).count, 5)
        }
        check(s)
        s.pointerMoved(to: s.layout.pointOnRay(degrees: 200, radiusFraction: 0.55)); check(s)
        s.pointerClicked(at: s.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)); check(s)
        s.pointerExitedVisibleArea(); check(s)
        s.moveKeyboardFocus(.next); check(s)
        s.enterPressed(); check(s)
        s.pointerMoved(to: Point2D(x: 80, y: 80)); check(s)
    }
    func testClockHasRealIntermediateProgressAndSettlesExactly() {
        var m = SharedGazeMotion(target: Point2D(x: 0, y: 0))
        m.retarget(Point2D(x: 1000, y: 500), at: 0, reduced: false)
        let a = m.advance(to: 0.04), b = m.advance(to: 0.08)
        XCTAssertGreaterThan(a.x, 0); XCTAssertLessThan(a.x, b.x); XCTAssertLessThan(b.x, 1000)
        for i in 3...60 { m.advance(to: Double(i)/30) }
        XCTAssertTrue(m.settled)
        XCTAssertEqual(m.position, Point2D(x: 1000, y: 500))
        let before = m
        m.advance(to: -1)
        XCTAssertEqual(m, before, "out-of-order timestamps cannot reverse progress")
    }
    func testFastPointerRetargetDoesNotResetProgressAndLeaveReenterIsContinuous() {
        var m = SharedGazeMotion(target: Point2D(x: 0, y: 0))
        for i in 1...120 {
            m.retarget(Point2D(x: 1000, y: 0), at: Double(i)/240, reduced: false)
            m.advance(to: Double(i)/240)
        }
        XCTAssertGreaterThan(m.position.x, 990, "240Hz inputs cannot indefinitely restart a duration")
        let before = m.position
        m.retarget(Point2D(x: -500, y: 100), at: m.time, reduced: false) // leave -> default
        XCTAssertEqual(m.position, before)
        let exitFrame = m.advance(to: m.time + 0.03)
        XCTAssertNotEqual(exitFrame, Point2D(x: -500, y: 100))
        m.retarget(Point2D(x: 600, y: 800), at: m.time, reduced: false) // interrupt/re-enter
        XCTAssertEqual(m.position, exitFrame)
        m.advance(to: m.time + 1)
        XCTAssertEqual(m.target, Point2D(x: 600, y: 800))
        XCTAssertTrue(m.settled)
    }
    func testReduceMotionSnapsIncludingExitWhileNormalClockContinues() {
        var m = SharedGazeMotion(target: Point2D(x: 0, y: 0))
        m.retarget(Point2D(x: 200, y: 80), at: 0.01, reduced: true)
        XCTAssertEqual(m.position, m.target)
        m.retarget(Point2D(x: 400, y: 1200), at: 0.02, reduced: true)
        XCTAssertTrue(m.settled)
        XCTAssertEqual(m.position, Point2D(x: 400, y: 1200))
    }
}
