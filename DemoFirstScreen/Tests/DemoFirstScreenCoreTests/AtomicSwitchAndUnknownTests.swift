import XCTest
@testable import DemoFirstScreenCore

final class AtomicSwitchAndUnknownTests: XCTestCase {
    func testFastPointerSwitchNeverMixesDirectoryInfoFields() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        let apps = session.hits.sector(id: "Applications")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: users))
        let first = session.displayedInfo
        XCTAssertEqual(first.id, "Users")
        XCTAssertEqual(first.name, "Users")
        XCTAssertEqual(first.sizeBytes, 100_000_000_000)

        session.pointerMoved(to: TestSupport.interiorPoint(of: apps))
        let second = session.displayedInfo
        XCTAssertEqual(second.id, "Applications")
        XCTAssertEqual(second.name, "Applications")
        XCTAssertEqual(second.sizeBytes, 20_000_000_000)
        XCTAssertNotEqual(second.sizeBytes, first.sizeBytes)
        XCTAssertEqual(second.activityText, DemoCopy.activityNotCollected)
        XCTAssertEqual(first.activityText, DemoCopy.activityNotCollected)
        // The whole info group is replaced; no mixed name/size pair is representable.
        XCTAssertFalse(second.name == "Applications" && second.sizeBytes == first.sizeBytes)
        XCTAssertFalse(second.name == first.name && second.sizeBytes != first.sizeBytes && second.id == first.id)
    }

    func testStaleGenerationCallbackMustNotWriteBack() throws {
        var session = try TestSupport.sessionFixture()
        let users = session.hits.sector(id: "Users")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: users))
        let stale = session.state.generation
        let library = session.hits.sector(id: "Library")!
        session.pointerMoved(to: TestSupport.interiorPoint(of: library))
        XCTAssertFalse(session.isCurrent(generation: stale))
        XCTAssertTrue(session.isCurrent(generation: session.state.generation))
        XCTAssertEqual(session.state.displayedID, "Library")
    }

    func testUnknownAndPartialAreNotZeroAndDoNotEnterDenominator() throws {
        let (a, b) = TestSupport.dates()
        let snapshot = DemoSnapshot(
            id: "partial-unknown",
            testOnly: true,
            label: "gate",
            startedAt: a,
            endedAt: b,
            timeZoneName: "America/Los_Angeles",
            caliber: .allocated,
            caliberNote: "test",
            apfsRootDataDedupVerified: true,
            nonOverlapVerified: true,
            activity: .notCollected,
            notes: [],
            items: [
                SnapshotItem(id: "A", name: "A", bytes: 100, errorCount: 0, readStatus: .reportedComplete),
                SnapshotItem(id: "B", name: "B", bytes: 50, errorCount: 3, readStatus: .partial),
                SnapshotItem(id: "C", name: "C", bytes: nil, errorCount: 1, readStatus: .unknown)
            ]
        )
        let chart = ChartabilityGate.evaluate(snapshot)
        guard case .chartable(let sectors, let denom) = chart else {
            return XCTFail("complete item A should chart alone")
        }
        XCTAssertEqual(denom, 100)
        XCTAssertEqual(sectors.map(\.id), ["A"])
        XCTAssertEqual(sectors[0].sweepDegrees, 180, accuracy: 1e-9)
        XCTAssertNotEqual(snapshot.items[1].knownBytes, 0)
        XCTAssertEqual(snapshot.items[1].knownBytes, 50)
        XCTAssertNil(snapshot.items[2].knownBytes)
        let info = InfoFactory(snapshot: snapshot, chartability: chart).info(for: "B")
        XCTAssertEqual(info.sizeBytes, 50)
        XCTAssertNotEqual(info.sizeText, "0 B")
        XCTAssertEqual(info.insufficiencyText, DemoCopy.partialUnknownTotal)
        XCTAssertEqual(info.activityText, DemoCopy.activityNotCollected)
    }

    func testProductionSnapshotUnknownIsNotZeroAndIsNotChartable() throws {
        let snapshot = try TestSupport.productionSnapshot()
        XCTAssertFalse(snapshot.testOnly)
        let chart = ChartabilityGate.evaluate(snapshot)
        XCTAssertFalse(chart.isChartable)
        if case .insufficient(let reason) = chart {
            XCTAssertTrue(reason.contains("不重叠") || reason.contains("不得图化"))
        } else {
            XCTFail("production du must not be chartable")
        }
        let factory = InfoFactory(snapshot: snapshot, chartability: chart)
        let overview = factory.overviewInfo()
        XCTAssertEqual(overview.insufficiencyText, DemoCopy.comparisonInsufficient)
        XCTAssertEqual(overview.sizeText, "")
        XCTAssertFalse(overview.sizeText.contains("200 GB"))
        XCTAssertFalse(overview.sizeText.contains("20/30/50/100"))
        XCTAssertEqual(overview.activityText, DemoCopy.activityNotCollected)
        XCTAssertEqual(overview.name, "")
        // Known values stay on the snapshot / itemInfo; overview is a minimal badge, not a list.
        // Partials are not replaced with 0, and the fixture proportions are not silently swapped in.
        let library = factory.info(for: "Library")
        XCTAssertEqual(library.sizeBytes, 8_785_653_760)
        XCTAssertNotEqual(library.sizeBytes, 0)
        XCTAssertEqual(library.insufficiencyText, "\(DemoCopy.comparisonInsufficient) · \(DemoCopy.partialUnknownTotal)")
        let apps = factory.info(for: "Applications")
        XCTAssertEqual(apps.sizeBytes, 34_276_593_664)
        XCTAssertEqual(apps.insufficiencyText, DemoCopy.comparisonInsufficient)
        XCTAssertFalse(apps.identityText.contains(DemoCopy.exampleNotLocal))
    }

    func testProductionLoaderRejectsTestOnly() throws {
        let fixture = try TestSupport.chartableFixture()
        XCTAssertTrue(fixture.testOnly)
        // The bundled production path must be the Eric snapshot, not the fixture.
        let production = try SnapshotLoader.loadBundledProduction()
        XCTAssertFalse(production.testOnly)
        XCTAssertEqual(production.id, "eric-du-20261121-readonly")
        XCTAssertNotEqual(production.id, fixture.id)
    }
}
