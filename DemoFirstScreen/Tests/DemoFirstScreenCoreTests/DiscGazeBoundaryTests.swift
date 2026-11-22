import XCTest
@testable import DemoFirstScreenCore

/// 15:53 supersedes old disc-only gaze tests; disc gating still applies to INFO.
final class DiscGazeBoundaryTests: XCTestCase {
    private func session() throws -> InteractionSession {
        InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
    }
    func testAllWindowRegionsFollowWithoutMakingThemSectorHits() throws {
        var s = try session()
        let movie = s.layout.pointOnRay(degrees: 200, radiusFraction: 0.55)
        s.pointerClicked(at: movie)
        for point in [Point2D(x: 120, y: 400), Point2D(x: 80, y: 80),
                      VectorEyeSpec.left.shell.center, s.layout.center,
                      Point2D(x: -250, y: 900)] { // letterbox in a wide window
            XCTAssertFalse(s.hits.isOnDisc(point))
            s.pointerMoved(to: point)
            let f = FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: true)
            XCTAssertTrue(f.eye.followsPointer)
            XCTAssertEqual(f.eye.resolvedTarget, point)
            XCTAssertNil(s.state.pointerPreviewID)
            XCTAssertEqual(s.state.lockedID, "Movies")
            XCTAssertEqual(f.info.id, "Movies")
        }
    }
    func testFocusIsNotExitAndReentryDoesNotResurrectPreview() throws {
        var s = try session(); let p = Point2D(x: 80, y: 80)
        s.pointerMoved(to: p); s.windowLostFocus()
        XCTAssertEqual(s.state.pointerLocation, p)
        XCTAssertNil(s.state.pointerPreviewID)
        XCTAssertNil(s.state.keyboardPreviewID)
        XCTAssertTrue(FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: true).eye.followsPointer)
        s.windowGainedFocus()
        XCTAssertEqual(s.state.pointerLocation, p)
        s.pointerExitedVisibleArea()
        let out = FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertFalse(out.eye.followsPointer)
        XCTAssertEqual(out.eye.resolvedTarget, out.eye.defaultTarget)
        XCTAssertEqual(out.eye.defaultTargetID, "Movies")
        s.pointerMoved(to: Point2D(x: 2100, y: 100))
        let again = FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertTrue(again.eye.followsPointer)
        XCTAssertEqual(again.eye.resolvedTarget, Point2D(x: 2100, y: 100))
    }
    func testNoCoordinateDoesNotInventInputAndOutsideFlagWins() throws {
        var s = try session()
        let initial = FramePresentation.make(session: s, motion: .reduced, pointerInsideWindow: true)
        XCTAssertFalse(initial.eye.followsPointer)
        s.pointerMoved(to: Point2D(x: 120, y: 400))
        let outside = FramePresentation.make(session: s, motion: .defaultMotion, pointerInsideWindow: false)
        XCTAssertEqual(outside.eye.resolvedTarget, initial.eye.defaultTarget)
    }
}
