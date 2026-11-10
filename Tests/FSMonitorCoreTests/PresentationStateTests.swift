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
        XCTAssertTrue(session.statusMessage?.hasPrefix("已停止监控") == true)
        XCTAssertFalse(session.statusMessage?.contains("扫描仍在继续") == true)

        // During sample transition, dual-task uses sampling label — not static "已停止".
        var dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(dual.monitoringLine, "监控：采样过渡中")
        XCTAssertEqual(SessionPresentation.primaryAction(for: session), .none)
        XCTAssertTrue(dual.combinedSummary.contains("扫描：复扫中") || dual.scanningLine?.contains("复扫") == true)

        session.stopMonitoring(processSample: sample([], at: 2))
        XCTAssertTrue(session.isScanning)
        XCTAssertTrue(session.statusMessage?.hasPrefix("已停止监控") == true)
        XCTAssertFalse(session.statusMessage?.contains("扫描仍在继续") == true)

        // After stop settles, static dual-task must say 未运行; scan-continue lives on live dual/scan strip.
        dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(dual.monitoringLine, "监控：未运行")
        XCTAssertTrue(dual.combinedSummary.contains("监控未运行，扫描仍在进行"))
        XCTAssertFalse(dual.combinedSummary.contains("监控：已停止"))

        // After scan finishes, statusMessage must not still claim scanning continues.
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true, capturedAt: fixedDate(3)), purpose: .rescan).accepted)
        XCTAssertFalse(session.isScanning)
        XCTAssertFalse(session.statusMessage?.contains("扫描仍在继续") == true)
        XCTAssertEqual(SessionPresentation.dualTaskStatus(for: session).monitoringLine, "监控：未运行")
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
        // F7 idle with valid baseline must keep dual-task chrome visible (not scan-only).
        XCTAssertTrue(SessionPresentation.shouldShowDualTaskChrome(for: session))

        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        let scanning = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertEqual(scanning.monitoringLine, "监控：未运行")
        XCTAssertTrue(scanning.combinedSummary.contains("监控未运行，扫描仍在进行"))
    }

    func testStopFeedbackNeverEmbedsScanContinuesInStatusMessage() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        session.beginMonitoring(processSample: sample([], at: 1))
        XCTAssertTrue(session.prepareScan(.rescan).accepted)

        session.markMonitoringStoppedAwaitingSample()
        XCTAssertEqual(session.statusMessage?.hasPrefix("已停止监控"), true)
        XCTAssertFalse(session.statusMessage?.contains("扫描仍在继续") == true)

        session.stopMonitoring(processSample: sample([], at: 2))
        XCTAssertEqual(session.statusMessage?.hasPrefix("已停止监控"), true)
        XCTAssertFalse(session.statusMessage?.contains("扫描仍在继续") == true)
        // Live dual-task still reports scan in progress independently of statusMessage.
        let dual = SessionPresentation.dualTaskStatus(for: session)
        XCTAssertTrue(session.isScanning)
        XCTAssertTrue(dual.combinedSummary.contains("扫描"))
    }

    func testDualTaskChromeVisibleForIdleBaselineAndHiddenBeforeBaselineIdle() {
        var session = MonitorSession()
        XCTAssertFalse(SessionPresentation.shouldShowDualTaskChrome(for: session))

        _ = session.selectDirectory(path: "/tmp/example")
        XCTAssertFalse(SessionPresentation.shouldShowDualTaskChrome(for: session))

        _ = session.prepareScan(.baseline)
        XCTAssertTrue(SessionPresentation.shouldShowDualTaskChrome(for: session))
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        XCTAssertTrue(SessionPresentation.shouldShowDualTaskChrome(for: session))
        XCTAssertEqual(SessionPresentation.dualTaskStatus(for: session).monitoringLine, "监控：未运行")
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

    func testConfirmationCopyMatchesNovaAddendum1134Verbatim() {
        XCTAssertEqual(SessionPresentation.changeDirectoryConfirmTitle, "更换监控目录？")
        XCTAssertEqual(
            SessionPresentation.changeDirectoryConfirmMessage,
            "更换后将停止当前监控、取消扫描，并清除本次会话中的基线、对照结果、操作证据和进程读写采样。不会删除磁盘文件。"
        )
        XCTAssertEqual(SessionPresentation.changeDirectoryConfirmAction, "更换目录")

        XCTAssertEqual(SessionPresentation.rebuildBaselineConfirmTitle, "重建基线？")
        XCTAssertEqual(
            SessionPresentation.rebuildBaselineConfirmMessage,
            "扫描成功后将替换现有基线和对照结果，并清空本次已记录的操作证据。扫描失败或取消会保留旧结果；正在运行的监控不会因此停止。"
        )
        XCTAssertEqual(SessionPresentation.rebuildBaselineConfirmAction, "重建基线")
    }

    func testRebuildConfirmsForAnyValidBaselineNotOnlyMonitoringOrEvidence() {
        var session = MonitorSession()
        XCTAssertFalse(SessionPresentation.shouldConfirmRebuildBaseline(for: session))

        _ = session.selectDirectory(path: "/tmp/example")
        XCTAssertFalse(SessionPresentation.shouldConfirmRebuildBaseline(for: session))

        _ = session.prepareScan(.baseline)
        XCTAssertTrue(session.finishScan(emptySnapshot(completed: true), purpose: .baseline).accepted)
        XCTAssertTrue(session.evidence.isEmpty)
        XCTAssertFalse(session.isMonitoring)
        // Idle valid baseline must still confirm — Nova 11:34.
        XCTAssertTrue(SessionPresentation.shouldConfirmRebuildBaseline(for: session))
    }

    func testPartialCoverageSummaryLabelsDoNotInviteSubtractingTotals() {
        let full = SessionPresentation.summaryCardCopy(partialCoverage: false)
        XCTAssertEqual(full.baselineTitle, "基线逻辑大小")
        XCTAssertEqual(full.currentTitle, "当前逻辑大小")
        XCTAssertEqual(full.deltaTitle, "逻辑增长")

        let partial = SessionPresentation.summaryCardCopy(partialCoverage: true)
        XCTAssertEqual(partial.baselineTitle, "基线扫描合计")
        XCTAssertEqual(partial.currentTitle, "当前可读合计")
        XCTAssertEqual(partial.deltaTitle, "可比较逻辑变化")
        XCTAssertTrue(partial.baselineCaptionHint.contains("不可直接相减"))
        XCTAssertTrue(partial.currentCaptionHint.contains("不可与基线合计直接相减"))
        XCTAssertTrue(partial.deltaCaptionHint.contains("未知项不计入确定增删"))
        // Example art numbers must never be hardcoded into presentation helpers.
        XCTAssertFalse(partial.baselineTitle.contains("1240"))
        XCTAssertFalse(partial.currentTitle.contains("1334"))
        XCTAssertFalse(partial.deltaTitle.contains("174"))

        XCTAssertFalse(
            SessionPresentation.usesPartialCoverageSummaryLabels(diff: nil, scanIssues: [])
        )
        let issue = ScanIssue(path: "secret", message: "无法读取")
        XCTAssertTrue(
            SessionPresentation.usesPartialCoverageSummaryLabels(diff: nil, scanIssues: [issue])
        )
        let gapDiff = SnapshotDiff(
            changes: [],
            logicalDelta: 0,
            allocatedDelta: 0,
            addedCount: 0,
            removedCount: 0,
            grownCount: 0,
            shrunkCount: 0,
            typeChangedCount: 0,
            unchangedCount: 0,
            coverageGapCount: 2
        )
        XCTAssertTrue(
            SessionPresentation.usesPartialCoverageSummaryLabels(diff: gapDiff, scanIssues: [])
        )
        XCTAssertEqual(EntryChangeKind.coverageGap.label, "覆盖缺口（未知，不可判断）")
    }

    func testCancelOrFailKeepsOldResultsAndDoesNotStopMonitoringFlag() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        _ = session.prepareScan(.baseline)
        let baseline = emptySnapshot(completed: true, capturedAt: fixedDate(10))
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        session.beginMonitoring(processSample: sample([], at: 1))
        XCTAssertTrue(session.isMonitoring)

        _ = session.prepareScan(.rescan)
        let failed = emptySnapshot(completed: false, cancelled: false, capturedAt: fixedDate(99))
        let result = session.finishScan(failed, purpose: .rescan)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(session.baseline?.capturedAt, baseline.capturedAt)
        XCTAssertTrue(session.showingStaleAcceptedResults)
        // Rebuild/rescan failure must not auto-stop monitoring.
        XCTAssertTrue(session.isMonitoring)
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
