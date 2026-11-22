import XCTest
@testable import DemoFirstScreenCore

final class ExampleInteractionTests: XCTestCase {
    func testExampleSourceIsIndependentOfProductionAndFixture() throws {
        let example = try SnapshotLoader.loadBundledExampleInteraction()
        let production = try SnapshotLoader.loadBundledProduction()
        let fixture = try TestSupport.chartableFixture()

        XCTAssertTrue(example.exampleInteraction)
        XCTAssertFalse(example.testOnly)
        XCTAssertEqual(example.id, "demo-example-five-sectors-20261121")
        XCTAssertEqual(example.items.count, 5)
        XCTAssertEqual(example.label, DemoCopy.exampleInteraction)

        XCTAssertFalse(production.exampleInteraction)
        XCTAssertFalse(production.testOnly)
        XCTAssertEqual(production.id, "eric-du-20261121-readonly")
        XCTAssertNotEqual(production.id, example.id)

        XCTAssertTrue(fixture.testOnly)
        XCTAssertFalse(fixture.exampleInteraction)
        XCTAssertNotEqual(fixture.id, example.id)
        XCTAssertEqual(fixture.items.count, 4)

        let exampleIDs = Set(example.items.map(\.id))
        let productionIDs = Set(production.items.map(\.id))
        XCTAssertTrue(exampleIDs.isDisjoint(with: productionIDs), "example directories must not reuse the real snapshot ids")
        XCTAssertFalse(example.items.map(\.bytes).contains(34_276_593_664))
        let exampleBytes = example.items.compactMap(\.knownBytes)
        XCTAssertFalse(exampleBytes.contains(20_000_000_000))
        XCTAssertFalse(exampleBytes.contains(100_000_000_000))
    }

    func testExampleChartsFiveSectorsWithOwnDenominatorAndNotProductionBytes() throws {
        let example = try SnapshotLoader.loadBundledExampleInteraction()
        let production = try SnapshotLoader.loadBundledProduction()
        let chart = ChartabilityGate.evaluate(example)
        guard case .chartable(let sectors, let denom) = chart else {
            return XCTFail("example interaction must be chartable")
        }
        XCTAssertEqual(sectors.count, 5)
        XCTAssertEqual(denom, 240_000_000_000)
        let sum = sectors.reduce(0.0) { $0 + $1.sweepDegrees }
        XCTAssertEqual(sum, 180.0, accuracy: 1e-9)
        XCTAssertEqual(sectors[0].id, "Movies")
        XCTAssertEqual(sectors[0].sweepDegrees, 54, accuracy: 1e-9)
        XCTAssertEqual(sectors[1].sweepDegrees, 45, accuracy: 1e-9)
        XCTAssertEqual(sectors[2].sweepDegrees, 36, accuracy: 1e-9)
        XCTAssertEqual(sectors[3].sweepDegrees, 27, accuracy: 1e-9)
        XCTAssertEqual(sectors[4].sweepDegrees, 18, accuracy: 1e-9)
        XCTAssertEqual(sectors[0].startDegrees, 180, accuracy: 1e-9)
        XCTAssertEqual(sectors[4].endDegrees, 360, accuracy: 1e-9)
        XCTAssertFalse(ChartabilityGate.evaluate(production).isChartable)
        // Production bytes never enter the example denominator.
        XCTAssertNotEqual(denom, production.items.compactMap(\.knownBytes).reduce(0, +))
    }

    func testExampleInfoKeepsSampleIdentityInEveryFocusStateAndOmitsInsufficientCopy() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        XCTAssertTrue(session.chartability.isChartable)
        let overview = session.displayedInfo
        XCTAssertTrue(overview.isOverview)
        // Internal provenance is retained; the on-screen badge is removed (Albert 05:22).
        XCTAssertEqual(overview.identityText, DemoCopy.exampleInteraction)
        XCTAssertNil(overview.onScreenIdentityText)
        XCTAssertNil(overview.insufficiencyText)
        XCTAssertEqual(overview.sizeText, "")
        XCTAssertEqual(overview.activityText, DemoCopy.activityNotCollected)
        XCTAssertTrue(overview.timeText.contains("示例时间"))

        let movies = session.hits.sector(id: "Movies")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: movies, layout: session.layout))
        let hover = session.displayedInfo
        XCTAssertEqual(hover.id, "Movies")
        XCTAssertEqual(hover.name, "影片")
        XCTAssertEqual(hover.sizeBytes, 72_000_000_000)
        XCTAssertEqual(hover.identityText, DemoCopy.exampleInteraction)
        XCTAssertNil(hover.onScreenIdentityText)
        XCTAssertNil(hover.insufficiencyText)
        XCTAssertEqual(hover.activityText, DemoCopy.activityNotCollected)
        XCTAssertTrue(hover.timeText.contains("示例时间"))

        session.pointerClicked(at: TestSupport.interiorPoint(of: movies, layout: session.layout))
        let locked = session.displayedInfo
        XCTAssertEqual(locked.id, "Movies")
        XCTAssertEqual(locked.identityText, DemoCopy.exampleInteraction)
        XCTAssertNil(locked.onScreenIdentityText)
        XCTAssertNil(locked.insufficiencyText)
        XCTAssertEqual(session.state.lockedID, "Movies")
    }

    func testLoadersRejectRoleMixing() throws {
        let fixture = try TestSupport.chartableFixture()
        XCTAssertThrowsError(try assertNotExample(fixture))
        let production = try SnapshotLoader.loadBundledProduction()
        XCTAssertFalse(production.exampleInteraction)
        XCTAssertEqual(try SnapshotLoader.loadBundledExampleInteraction().items.count, 5)
    }

    func testHoverDoesNotChangeActivityToRecording() throws {
        var session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let pictures = session.hits.sector(id: "Pictures")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: pictures, layout: session.layout))
        XCTAssertEqual(session.displayedInfo.activityText, DemoCopy.activityNotCollected)
        XCTAssertEqual(session.snapshot.activity, .notCollected)
    }

    private func assertNotExample(_ snapshot: DemoSnapshot) throws {
        if snapshot.exampleInteraction {
            throw SnapshotLoadError.rejectedTestOnlyAsExample
        }
        if snapshot.testOnly {
            throw SnapshotLoadError.rejectedTestOnlyAsExample
        }
    }
}
