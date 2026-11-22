import XCTest
@testable import DemoFirstScreenCore

final class InteractionTrajectoryTests: XCTestCase {
    func testInitialPAndLAreNil() throws {
        let session = try TestSupport.sessionFixture()
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertNil(session.state.lockedID)
        XCTAssertEqual(session.state.activeInput, .none)
        XCTAssertNil(session.state.displayedID)
        XCTAssertNil(session.state.actualObservationID)
        XCTAssertTrue(session.displayedInfo.isOverview)
    }

    func testPointerLockAHoverBExitClearsPReturnsToA() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        let system = session.hits.sector(id: "System")!
        let a = TestSupport.interiorPoint(of: users)
        let b = TestSupport.interiorPoint(of: system)

        session.pointerClicked(at: a)
        XCTAssertEqual(session.state.lockedID, "Users")
        XCTAssertEqual(session.state.pointerPreviewID, "Users")
        XCTAssertEqual(session.state.displayedID, "Users")
        let observation = session.state.actualObservationID

        session.pointerMoved(to: b)
        XCTAssertEqual(session.state.pointerPreviewID, "System")
        XCTAssertEqual(session.state.lockedID, "Users", "H/P of B must not change L")
        XCTAssertEqual(session.state.displayedID, "System", "display prefers P over L")
        XCTAssertEqual(session.state.actualObservationID, observation, "preview must not change actual observation")

        session.pointerMoved(to: Point2D(x: 10, y: 10)) // outside platter
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.lockedID, "Users")
        XCTAssertEqual(session.state.displayedID, "Users")
    }

    func testClickBThenExitStaysBAndRepeatClickDoesNotUnlock() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        let system = session.hits.sector(id: "System")!
        session.pointerClicked(at: TestSupport.interiorPoint(of: users))
        session.pointerClicked(at: TestSupport.interiorPoint(of: system))
        XCTAssertEqual(session.state.lockedID, "System")
        session.pointerExitedVisibleArea()
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.lockedID, "System")
        XCTAssertEqual(session.state.displayedID, "System")

        session.pointerClicked(at: TestSupport.interiorPoint(of: system))
        XCTAssertEqual(session.state.lockedID, "System")
        XCTAssertEqual(session.state.displayedID, "System")
    }

    func testKeyboardTabPreviewsAndStationaryPointerDoesNotSteal() throws {
        var session = try TestSupport.sessionFixture()
        session.moveKeyboardFocus(.next)
        XCTAssertEqual(session.state.activeInput, .keyboard)
        XCTAssertEqual(session.state.keyboardPreviewID, "Users")
        XCTAssertNil(session.state.pointerPreviewID)
        let preview = session.state.displayedID
        // A still pointer must not call pointerMoved. No steal.
        XCTAssertEqual(session.state.activeInput, .keyboard)
        XCTAssertEqual(session.state.displayedID, preview)
        XCTAssertEqual(session.state.displayedID, "Users")
    }

    func testRealPointerMoveClearsKAndDoesNotReviveItOnFallback() throws {
        var session = try TestSupport.sessionFixture()
        session.moveKeyboardFocus(.next) // Users
        session.moveKeyboardFocus(.next) // System
        XCTAssertEqual(session.state.keyboardPreviewID, "System")
        let users = session.hits.sector(id: "Users")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: users))
        XCTAssertEqual(session.state.activeInput, .pointer)
        XCTAssertEqual(session.state.pointerPreviewID, "Users")
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertEqual(session.state.retainedKeyboardFocusID, "System")

        session.pointerExitedVisibleArea()
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.activeInput, .none)
        XCTAssertNil(session.state.keyboardPreviewID, "fallback must not revive the previous keyboard preview")
        XCTAssertNil(session.state.displayedID)
        XCTAssertTrue(session.displayedInfo.isOverview)
    }

    func testEnterLocksKeyboardFocusAndClickLocksHit() throws {
        var session = try TestSupport.sessionFixture()
        session.moveKeyboardFocus(.next)
        session.enterPressed()
        XCTAssertEqual(session.state.lockedID, "Users")
        let library = session.hits.sector(id: "Library")!
        session.pointerClicked(at: TestSupport.interiorPoint(of: library))
        XCTAssertEqual(session.state.lockedID, "Library")
        XCTAssertEqual(session.state.activeInput, .pointer)
        XCTAssertNil(session.state.keyboardPreviewID)
    }

    func testPointerExitDoesNotClearKeyboardPreviewButWindowBlurClearsPKKeepsL() throws {
        var session = try TestSupport.sessionFixture()
        session.moveKeyboardFocus(.next)
        session.enterPressed()
        XCTAssertEqual(session.state.lockedID, "Users")
        session.moveKeyboardFocus(.next) // System preview over Users lock
        XCTAssertEqual(session.state.keyboardPreviewID, "System")
        session.pointerExitedVisibleArea()
        XCTAssertEqual(session.state.keyboardPreviewID, "System")
        XCTAssertEqual(session.state.activeInput, .keyboard)
        XCTAssertEqual(session.state.displayedID, "System")

        session.windowLostFocus()
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertEqual(session.state.activeInput, .none)
        XCTAssertEqual(session.state.lockedID, "Users")
        XCTAssertEqual(session.state.displayedID, "Users")

        session.windowGainedFocus()
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertNil(session.state.pointerPreviewID)
        XCTAssertEqual(session.state.displayedID, "Users")
    }

    func testKeyboardFocusLeavingComponentClearsK() throws {
        var session = try TestSupport.sessionFixture()
        session.moveKeyboardFocus(.next)
        session.keyboardFocusLeftComponent()
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertEqual(session.state.activeInput, .none)
    }

    func testInsufficientSnapshotHasNoSectorHoverOrLock() throws {
        var session = InteractionSession(snapshot: try TestSupport.productionSnapshot())
        XCTAssertFalse(session.chartability.isChartable)
        XCTAssertTrue(session.traversableIDs.isEmpty)
        let point = TestSupport.layout.visibleInteriorPoint(startDegrees: 180, endDegrees: 270)
        session.pointerMoved(to: point)
        XCTAssertNil(session.state.pointerPreviewID)
        session.pointerClicked(at: point)
        XCTAssertNil(session.state.lockedID)
        session.moveKeyboardFocus(.next)
        XCTAssertNil(session.state.keyboardPreviewID)
        XCTAssertEqual(session.displayedInfo.insufficiencyText, DemoCopy.comparisonInsufficient)
    }
}
