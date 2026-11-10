import Foundation
import XCTest
@testable import FSMonitorCore

final class PresentationStateTests: XCTestCase {
    func testPrimaryActionFollowsStateTable() {
        var session = MonitorSession()
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .chooseDirectory)
        XCTAssertNotEqual(SessionPresentation.primaryAction(for: session), .rescan)

        _ = session.selectDirectory(path: "/tmp/example")
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .establishBaseline)
        XCTAssertNotEqual(SessionPresentation.primaryAction(for: session), .rescan)

        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)
        XCTAssertEqual(session.activeScanPurpose, .baseline)
        XCTAssertNotEqual(SessionPresentation.primaryAction(for: session), .rescan)

        let baseline = emptySnapshot(completed: true)
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .startMonitoring)
        XCTAssertNotEqual(SessionPresentation.primaryAction(for: session), .rescan)

        session.beginMonitoring(processSample: sample([], at: 1))
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .rescan)

        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)
        XCTAssertNotEqual(SessionPresentation.primaryAction(for: session), .rescan)
        XCTAssertTrue(session.canStopMonitoring)
    }

    func testRescanIsNeverEmphasizedWhenDisabledByState() {
        // Mirrors ContentView: borderedProminent only when primaryAction == .rescan.
        var session = MonitorSession()
        let emphasizeRescan = { SessionPresentation.primaryAction(for: session) == .rescan }

        XCTAssertFalse(emphasizeRescan()) // no directory
        _ = session.selectDirectory(path: "/tmp/example")
        XCTAssertFalse(emphasizeRescan()) // no baseline
        _ = session.prepareScan(.baseline)
        XCTAssertFalse(emphasizeRescan()) // scanning
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        XCTAssertFalse(emphasizeRescan()) // baseline ready, not monitoring
        session.beginProcessSampleWait(message: "采样")
        XCTAssertFalse(emphasizeRescan()) // sample transition
        session.isProcessSamplePending = false
        session.beginMonitoring(processSample: sample([], at: 1))
        XCTAssertTrue(emphasizeRescan()) // monitoring idle — only then
        XCTAssertTrue(session.canRescan)
    }

    func testSamplePendingHasNoPrimaryButCancelScanRemainsPossible() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)

        session.beginProcessSampleWait(message: "采样中")
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)
        XCTAssertFalse(session.canRescan)
        XCTAssertFalse(session.canStartMonitoring)
        XCTAssertFalse(session.canStopMonitoring)

        // Scan can still be in flight under sample wait in the UI; request cancel must work.
        session.isScanning = true
        session.activeScanPurpose = .rescan
        session.requestScanCancel()
        XCTAssertTrue(session.scanCancelRequested)
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)
        let dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertTrue(dual.combinedSummary.contains("取消中") || dual.scanningLine?.contains("取消") == true)
    }

    func testStopMonitoringWhileScanningKeepsScanAndShowsDualStatus() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        session.beginMonitoring(processSample: sample([], at: 1))
        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        XCTAssertTrue(session.isMonitoring)
        XCTAssertTrue(session.isScanning)

        session.markMonitoringStoppedAwaitingSample()
        XCTAssertFalse(session.isMonitoring)
        XCTAssertTrue(session.isScanning)
        XCTAssertTrue(session.statusMessage?.contains("已停止监控") == true)
        XCTAssertTrue(session.statusMessage?.contains("扫描仍在继续") == true)

        // During sample transition, dual-task uses sampling label — not static "已停止".
        var dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(dual.monitoringLine, "监控：采样过渡中")
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)

        session.stopMonitoring(processSample: sample([], at: 2))
        XCTAssertTrue(session.isScanning)
        XCTAssertTrue(session.statusMessage?.contains("已停止监控") == true)
        XCTAssertTrue(session.statusMessage?.contains("扫描仍在继续") == true)

        // After stop settles, static dual-task must say 未运行 (may never have been started either).
        dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(dual.monitoringLine, "监控：未运行")
        XCTAssertTrue(dual.combinedSummary.contains("监控未运行，扫描仍在进行"))
        XCTAssertFalse(dual.combinedSummary.contains("监控：已停止"))
    }

    func testBaselineWithoutEverMonitoringUsesNotRunningNotStopped() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        XCTAssertFalse(session.isMonitoring)

        let idle = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(idle.monitoringLine, "监控：未运行")
        XCTAssertFalse(idle.combinedSummary.contains("已停止"))

        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        let scanning = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(scanning.monitoringLine, "监控：未运行")
        XCTAssertTrue(scanning.combinedSummary.contains("监控未运行，扫描仍在进行"))
    }

    func testCancelOrFailDoesNotAdoptIncompleteOrFakeSuccessTime() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        let baseline = emptySnapshot(completed: true, capturedAt: fixedDate(10))
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        let baselineTime = session.baseline?.capturedAt

        _ = session.prepareScan(.rescan)
        let cancelled = emptySnapshot(completed: false, cancelled: true, capturedAt: fixedDate(99))
        let result = session.finishScan(cancelled, purpose: .rescan)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(session.baseline?.capturedAt, baselineTime)
        XCTAssertEqual(session.current?.capturedAt, baselineTime)
        XCTAssertTrue(session.showingStaleAcceptedResults)
        XCTAssertFalse(session.statusMessage?.contains("复扫完成") == true)
        XCTAssertTrue(session.statusMessage?.contains("未更新结果") == true)
    }

    func testDirectoryChangeClearFactsAreDocumentedFromSourceBehavior() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/a")
        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        session.beginMonitoring(processSample: sample([], at: 1))
        session.appendEvidence(
            OperationEvidence.make(
                id: 1,
                observedAt: fixedDate(2),
                relativePath: "x",
                rawFlags: 0,
                streamEventID: nil
            )
        )
        XCTAssertFalse(session.evidence.isEmpty)

        _ = session.selectDirectory(path: "/tmp/b")
        XCTAssertNil(session.baseline)
        XCTAssertNil(session.current)
        XCTAssertTrue(session.evidence.isEmpty)
        XCTAssertFalse(session.isMonitoring)
        XCTAssertFalse(SessionPresentation.directoryChangeClears.isEmpty)
        XCTAssertTrue(SessionPresentation.exitRetentionFact.contains("不保留"))
    }

    private func emptySnapshot(
        completed: Bool,
        cancelled: Bool = false,
        capturedAt: Date = fixedDate(1)
    ) -> SpaceSnapshot {
        SpaceSnapshot(
            selectedPath: "/tmp/example",
            rootPath: "/tmp/example",
            rootResolutionNote: nil,
            breadthWarning: nil,
            capturedAt: capturedAt,
            entriesByPath: [:],
            issues: [],
            completed: completed,
            cancelled: cancelled,
            failureReason: cancelled ? "扫描已取消。" : (completed ? nil : "失败"),
            totalLogicalBytes: 0,
            totalAllocatedBytes: 0,
            regularFileCount: 0,
            directoryCount: 1,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
    }
}
