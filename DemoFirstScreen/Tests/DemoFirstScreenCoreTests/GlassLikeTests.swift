import XCTest
@testable import DemoFirstScreenCore

final class GlassLikeTests: XCTestCase {
    func testReducedTransparencyIsSolidAndHasNoGloss() {
        let reduced = GlassLikePolicy.highContrast
        XCTAssertEqual(reduced.rimSpecularity, 0)
        XCTAssertEqual(reduced.hoverGloss, 0)
        XCTAssertEqual(reduced.hoverShade, 0)
        XCTAssertEqual(reduced.platterGlow, 0)
        XCTAssertEqual(reduced.scleraSheen, 0)
        XCTAssertEqual(reduced.infoFillOpacity, 1.0)
        XCTAssertEqual(reduced.infoHighlight, 0)
    }

    func testStandardPolicyIsRestrainedNotFullyOpaqueInfo() {
        let standard = GlassLikePolicy.standard
        XCTAssertGreaterThan(standard.rimSpecularity, 0)
        XCTAssertLessThan(standard.rimSpecularity, 0.5)
        XCTAssertGreaterThan(standard.hoverGloss, 0)
        XCTAssertLessThan(standard.hoverGloss, 0.25)
        XCTAssertGreaterThan(standard.infoFillOpacity, 0.7)
        XCTAssertLessThan(standard.infoFillOpacity, 1.0)
        XCTAssertGreaterThan(standard.scleraSheen, 0)
    }

    func testGlassLikeDoesNotAlterGazeOrSectorNames() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let a = session.layout.pointOnRay(degrees: 190, radiusFraction: 0.50)
        let b = session.layout.pointOnRay(degrees: 220, radiusFraction: 0.58)
        session.pointerMoved(to: a)
        let fa = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        session.pointerMoved(to: b)
        let fb = FramePresentation.make(session: session, motion: .defaultMotion, pointerInsideWindow: true)
        XCTAssertEqual(fa.highlightID, "Movies")
        XCTAssertNotEqual(fa.eye.leftPupilOffset, fb.eye.leftPupilOffset)
        XCTAssertEqual(fa.eye.leftShellCenter, fb.eye.leftShellCenter)
        XCTAssertEqual(session.snapshot.items.map(\.name), ["影片", "归档", "文稿", "图片", "项目"])
        _ = GlassLikePolicy.standard
    }
}
