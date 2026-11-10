import Foundation
import XCTest
@testable import FSMonitorCore

final class DiffSessionAttributionTests: XCTestCase {
    func testRescanExplainsGrowthWithoutScanningOnSelection() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        let file = root.appendingPathComponent("logs/app.txt")
        let baselineSize = try writeMarkedFile(at: file, extraBytes: 20)

        var session = MonitorSession()
        XCTAssertNil(session.baseline)
        XCTAssertFalse(session.isScanning)
        XCTAssertEqual(session.report.claimsCompletePhysicalAttribution, false)
        XCTAssertTrue(session.statusMessage?.contains("不会扫描") == true)

        let tooEarly = session.prepareScan(.baseline)
        XCTAssertFalse(tooEarly.accepted)
        XCTAssertFalse(session.isScanning)

        XCTAssertTrue(session.selectDirectory(path: root.path).accepted)
        XCTAssertNil(session.baseline)
        XCTAssertFalse(session.isScanning)

        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        let baseline = DirectoryScanner.scan(root: root, cancellation: ScanCancellation(), now: fixedDate(1))
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        XCTAssertEqual(session.baseline?.totalLogicalBytes, Int64(baselineSize))
        XCTAssertEqual(session.diff?.logicalDelta, 0)

        let grown = try writeMarkedFile(at: file, extraBytes: 100)
        let added = try writeMarkedFile(at: root.appendingPathComponent("logs/new.txt"), extraBytes: 5)
        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        let current = DirectoryScanner.scan(root: root, cancellation: ScanCancellation(), now: fixedDate(2))
        XCTAssertTrue(session.finishScan(current, purpose: .rescan).accepted)

        let expectedDelta = Int64(grown + added - baselineSize)
        XCTAssertEqual(session.diff?.logicalDelta, expectedDelta)
        XCTAssertEqual(session.current?.totalLogicalBytes, Int64(grown + added))
        let rollup = session.rollups.first { $0.relativePath == "logs" }
        XCTAssertEqual(rollup?.logicalDelta, expectedDelta)
        let sorted = ChangeSorting.sort(session.diff?.changes.filter { $0.change != .unchanged } ?? [], by: .growthDescending)
        XCTAssertGreaterThanOrEqual(sorted.count, 2)
        XCTAssertGreaterThanOrEqual(sorted[0].logicalDelta, sorted[1].logicalDelta)
        let byPath = Dictionary(uniqueKeysWithValues: (session.diff?.changes ?? []).map { ($0.relativePath, $0) })
        XCTAssertEqual(byPath["logs/app.txt"]?.logicalDelta, Int64(grown - baselineSize))
        XCTAssertEqual(byPath["logs/new.txt"]?.change, .added)
        XCTAssertEqual(byPath["logs/new.txt"]?.logicalDelta, Int64(added))
        XCTAssertFalse(session.report.claimsCompletePhysicalAttribution)
        XCTAssertTrue(session.report.statements.contains { $0.contains("100%") })
    }

    func testCancelledRescanDoesNotReplaceBaseline() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        _ = try writeMarkedFile(at: root.appendingPathComponent("keep.txt"), extraBytes: 12)
        var session = MonitorSession()
        XCTAssertTrue(session.selectDirectory(path: root.path).accepted)
        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        let baseline = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        let before = session.baseline?.totalLogicalBytes

        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        let cancellation = ScanCancellation()
        cancellation.cancel()
        let partial = DirectoryScanner.scan(root: root, cancellation: cancellation)
        let result = session.finishScan(partial, purpose: .rescan)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(session.baseline?.totalLogicalBytes, before)
        XCTAssertEqual(session.current?.totalLogicalBytes, before)
        XCTAssertTrue(session.lastError?.contains("取消") == true)
        XCTAssertTrue(session.showingStaleAcceptedResults)
        XCTAssertFalse(session.isScanning)
    }

    func testProcessSamplePendingBlocksOverlappingActions() {
        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example-selected-only")
        let emptyBaseline = SpaceSnapshot(
            selectedPath: "/tmp/example-selected-only",
            rootPath: "/tmp/example-selected-only",
            rootResolutionNote: nil,
            breadthWarning: nil,
            capturedAt: fixedDate(1),
            entriesByPath: [:],
            issues: [],
            completed: true,
            cancelled: false,
            failureReason: nil,
            totalLogicalBytes: 0,
            totalAllocatedBytes: 0,
            regularFileCount: 0,
            directoryCount: 1,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        XCTAssertTrue(session.finishScan(emptyBaseline, purpose: .baseline).accepted)
        XCTAssertTrue(session.canStartMonitoring)

        session.beginProcessSampleWait(message: "采样中")
        XCTAssertTrue(session.isProcessSamplePending)
        XCTAssertFalse(session.canStartMonitoring)
        XCTAssertFalse(session.canEstablishBaseline)
        XCTAssertFalse(session.canRescan)
        XCTAssertFalse(session.validateStartMonitoring().accepted)
        XCTAssertFalse(session.prepareScan(.rescan).accepted)

        session.beginMonitoring(processSample: sample([], at: 2, listError: nil))
        XCTAssertFalse(session.isProcessSamplePending)
        XCTAssertTrue(session.isMonitoring)
        XCTAssertTrue(session.canStopMonitoring)

        session.markMonitoringStoppedAwaitingSample()
        XCTAssertTrue(session.isProcessSamplePending)
        XCTAssertFalse(session.canStartMonitoring)
        XCTAssertFalse(session.canStopMonitoring)
        session.stopMonitoring(processSample: sample([], at: 3, listError: nil))
        XCTAssertFalse(session.isProcessSamplePending)
        XCTAssertTrue(session.canStartMonitoring)
    }

    func testStaleFinishDoesNotMutateNewSelection() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        var session = MonitorSession()
        XCTAssertTrue(session.selectDirectory(path: root.path).accepted)
        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        XCTAssertTrue(session.selectDirectory(path: root.path).accepted)
        let snapshot = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())
        let result = session.finishScan(snapshot, purpose: .baseline)
        XCTAssertFalse(result.accepted)
        XCTAssertNil(session.baseline)
        XCTAssertTrue(session.statusMessage?.contains("建立基线") == true)
    }

    func testPathContainmentRejectsPrefixSiblings() {
        XCTAssertTrue(PathContainment.isInside(rootPath: "/tmp/a", candidatePath: "/tmp/a/b"))
        XCTAssertFalse(PathContainment.isInside(rootPath: "/tmp/a", candidatePath: "/tmp/a-b"))
        XCTAssertFalse(PathContainment.isInside(rootPath: "/tmp/a", candidatePath: "/tmp/a/../etc/passwd"))
        XCTAssertEqual(PathContainment.relative(rootPath: "/tmp/a", candidatePath: "/tmp/a"), ".")
        XCTAssertEqual(PathContainment.relative(rootPath: "/tmp/a", candidatePath: "/tmp/a/b"), "b")
    }

    func testSortingTiesBreakByPath() {
        let changes = [
            change("b", delta: 5, current: 5),
            change("a", delta: 5, current: 9),
            change("c", delta: 1, current: 1)
        ]
        XCTAssertEqual(ChangeSorting.sort(changes, by: .growthDescending).map(\.relativePath), ["a", "b", "c"])
        XCTAssertEqual(ChangeSorting.sort(changes, by: .currentSizeDescending).map(\.relativePath), ["a", "b", "c"])
        XCTAssertEqual(ChangeSorting.sort(changes, by: .pathAscending).map(\.relativePath), ["a", "b", "c"])
    }

    func testByteFormatting() {
        XCTAssertEqual(ByteFormatting.signed(from: 0), "0 字节")
        XCTAssertEqual(ByteFormatting.signed(from: 1024), "1.0 KB")
        XCTAssertEqual(ByteFormatting.signed(from: 1536), "1.5 KB")
        XCTAssertEqual(ByteFormatting.signed(from: -2048), "-2.0 KB")
        XCTAssertEqual(ByteFormatting.optionalUnsigned(nil), "不可获得")
    }

    func testProcessDeltasAreWholeProcessAndOmitMissingCounters() {
        let start = sample([
            reading(pid: 10, name: "writer", read: 100, write: 50, logical: 80),
            reading(pid: 11, name: "quiet", read: 5, write: 5, logical: 5),
            reading(pid: 12, name: "blocked", unavailable: "proc_pid_rusage 失败"),
            reading(pid: 13, name: "old-name", read: 1, write: 1, logical: 1),
            reading(pid: 14, name: "reset", read: 90, write: 90, logical: 90),
            reading(pid: 16, name: "partial", write: 1)
        ], at: 1)
        let end = sample([
            reading(pid: 10, name: "writer", read: 140, write: 90, logical: 100),
            reading(pid: 11, name: "quiet", read: 5, write: 5, logical: 5),
            reading(pid: 12, name: "blocked", unavailable: "proc_pid_rusage 失败"),
            reading(pid: 13, name: "new-name", read: 9, write: 9, logical: 9),
            reading(pid: 14, name: "reset", read: 10, write: 10, logical: 10),
            reading(pid: 15, name: "newbie", read: 3, write: 3, logical: 3),
            reading(pid: 16, name: "partial", write: 4)
        ], at: 2)

        let result = ProcessIOCorrelation.correlate(from: start, to: end)
        XCTAssertEqual(result.deltas.map(\.pid), [10, 16])
        XCTAssertEqual(result.deltas[0].wholeProcessReadDelta, 40)
        XCTAssertEqual(result.deltas[0].wholeProcessWriteDelta, 40)
        XCTAssertNil(result.deltas[1].wholeProcessReadDelta)
        XCTAssertEqual(result.deltas[1].wholeProcessWriteDelta, 3)
        XCTAssertEqual(result.deltas[0].scopeNote, ProcessIOCorrelation.scopeNote)
        XCTAssertTrue(result.deltas[0].scopeNote.contains("不是目标目录"))
        XCTAssertEqual(result.omittedBecauseUnchanged, 1)
        XCTAssertEqual(result.omittedBecauseUnavailable, 2)
        XCTAssertEqual(result.omittedBecausePIDReuse, 1)
        XCTAssertEqual(result.omittedBecauseNewOrExited, 1)
    }

    func testProcessDisplayTruncatesWithoutInventingZeros() {
        let startReadings = (1...5).map { reading(pid: Int32($0), name: "p\($0)", read: 0, write: 0, logical: 0) }
        let endReadings = (1...5).map { reading(pid: Int32($0), name: "p\($0)", read: 0, write: UInt64($0), logical: 0) }
        let result = ProcessIOCorrelation.correlate(
            from: sample(startReadings, at: 1),
            to: sample(endReadings, at: 2),
            displayLimit: 2
        )
        XCTAssertEqual(result.deltas.map(\.pid), [5, 4])
        XCTAssertEqual(result.truncatedCount, 3)
        XCTAssertTrue(result.deltas.allSatisfy { $0.wholeProcessWriteDelta != nil })
    }

    func testAttributionPhrasesAndEvidenceHaveNoPID() {
        let required = [
            "全进程",
            "不是目标目录",
            "FSEvents",
            "不提供 PID",
            "不是因果关系",
            "100%",
            "Endpoint Security",
            "root",
            "不会删除文件",
            "不会关闭 SIP"
        ]
        let text = AttributionLimits.statements.joined(separator: "\n")
        for phrase in required {
            XCTAssertTrue(text.contains(phrase), phrase)
        }
        let evidence = OperationEvidence.make(
            id: 1,
            observedAt: fixedDate(3),
            relativePath: "logs/app.txt",
            rawFlags: FSEventFlag.itemModified.rawValue | FSEventFlag.itemIsFile.rawValue,
            streamEventID: 99
        )
        XCTAssertEqual(evidence.limitation, FSEventFlagDecoder.noPIDLimitation)
        XCTAssertTrue(evidence.flagNames.contains("内容修改"))
        XCTAssertTrue(evidence.flagNames.contains("文件"))
        XCTAssertFalse(FSEventFlagDecoder.includesProcessIdentifier)
        XCTAssertFalse(evidence.flagNames.contains { $0.contains("PID") })

        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/fs-monitor-not-scanned")
        XCTAssertNil(session.baseline)
        let report = session.report
        XCTAssertFalse(report.claimsCompletePhysicalAttribution)
        XCTAssertEqual(report.statements, AttributionLimits.statements)
    }

    func testMonitoringRequiresBaselineAndLabelsProcessWindow() {
        var session = MonitorSession()
        XCTAssertFalse(session.validateStartMonitoring().accepted)
        _ = session.selectDirectory(path: "/tmp/example-selected-only")
        XCTAssertNil(session.baseline)
        XCTAssertFalse(session.validateStartMonitoring().accepted)

        let emptyBaseline = SpaceSnapshot(
            selectedPath: "/tmp/example-selected-only",
            rootPath: "/tmp/example-selected-only",
            rootResolutionNote: nil,
            breadthWarning: nil,
            capturedAt: fixedDate(1),
            entriesByPath: [:],
            issues: [],
            completed: true,
            cancelled: false,
            failureReason: nil,
            totalLogicalBytes: 0,
            totalAllocatedBytes: 0,
            regularFileCount: 0,
            directoryCount: 1,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        XCTAssertTrue(session.finishScan(emptyBaseline, purpose: .baseline).accepted)
        XCTAssertTrue(session.validateStartMonitoring().accepted)
        let unavailable = sample([], at: 2, listError: "proc_listallpids 失败。没有可展示的全进程计数。")
        session.beginMonitoring(processSample: unavailable)
        XCTAssertTrue(session.isMonitoring)
        XCTAssertNil(session.correlation)
        XCTAssertTrue(session.statusMessage?.contains("proc_listallpids") == true)
        session.markMonitoringStoppedAwaitingSample()
        session.stopMonitoring(processSample: unavailable)
        XCTAssertFalse(session.isMonitoring)
        XCTAssertNil(session.correlation?.deltas.first)
        XCTAssertFalse(session.report.claimsCompletePhysicalAttribution)
    }

    func testEvidenceOverlapIsNotRootWideAndFeedsTheReport() {
        XCTAssertFalse(PathOverlap.overlaps(entryPath: "a.txt", eventPath: "."))
        XCTAssertTrue(PathOverlap.overlaps(entryPath: "sub/a.txt", eventPath: "sub"))
        XCTAssertTrue(PathOverlap.overlaps(entryPath: "sub", eventPath: "sub/a.txt"))
        XCTAssertFalse(PathOverlap.overlaps(entryPath: "sub", eventPath: "subdir"))

        let baseline = snapshot(entries: [
            entry("sub/a.txt", size: 10),
            entry("other.txt", size: 4)
        ], total: 14)
        let current = snapshot(entries: [
            entry("sub/a.txt", size: 30),
            entry("other.txt", size: 4)
        ], total: 34)
        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let evidence = [
            OperationEvidence.make(id: 1, observedAt: fixedDate(1), relativePath: ".", rawFlags: FSEventFlag.mustScanSubDirs.rawValue, streamEventID: 1),
            OperationEvidence.make(id: 2, observedAt: fixedDate(2), relativePath: "sub/a.txt", rawFlags: FSEventFlag.itemModified.rawValue, streamEventID: 2)
        ]
        XCTAssertEqual(PathOverlap.growthPathsOverlappingEvidence(diff: diff, evidence: evidence), 1)

        var session = MonitorSession()
        _ = session.selectDirectory(path: "/tmp/example")
        XCTAssertTrue(session.prepareScan(.baseline).accepted)
        XCTAssertTrue(session.finishScan(baseline, purpose: .baseline).accepted)
        XCTAssertTrue(session.prepareScan(.rescan).accepted)
        XCTAssertTrue(session.finishScan(current, purpose: .rescan).accepted)
        session.appendEvidence(evidence[0])
        session.appendEvidence(evidence[1])
        XCTAssertEqual(session.report.growthPathsOverlappingEvents, 1)
        XCTAssertEqual(session.report.evidenceCount, 2)
        XCTAssertFalse(session.report.claimsCompletePhysicalAttribution)
    }

    func testEvidenceRetentionDropsOldest() {
        var session = MonitorSession()
        for index in 0..<(MonitorSession.evidenceRetentionLimit + 2) {
            session.appendEvidence(OperationEvidence.make(
                id: UInt64(index),
                observedAt: fixedDate(TimeInterval(index)),
                relativePath: "f\(index)",
                rawFlags: FSEventFlag.itemCreated.rawValue,
                streamEventID: nil
            ))
        }
        XCTAssertEqual(session.evidence.count, MonitorSession.evidenceRetentionLimit)
        XCTAssertEqual(session.evidenceDroppedCount, 2)
        XCTAssertEqual(session.evidence.first?.id, 2)
    }

    private func change(_ path: String, delta: Int64, current: Int64) -> EntryChange {
        EntryChange(
            relativePath: path,
            change: delta > 0 ? .grown : .unchanged,
            baselineLogical: current - delta,
            currentLogical: current,
            logicalDelta: delta,
            baselineAllocated: nil,
            currentAllocated: nil,
            kind: .regularFile,
            countsTowardTotal: true,
            note: nil
        )
    }

    private func entry(_ path: String, size: Int64) -> DirectoryEntry {
        DirectoryEntry(
            relativePath: path,
            kind: .regularFile,
            logicalSize: size,
            allocatedSize: size,
            modifiedAt: nil,
            device: 1,
            inode: UInt64(path.utf8.reduce(UInt64(1)) { $0 + UInt64($1) }),
            countsTowardTotal: true,
            hardLinkNote: nil
        )
    }

    private func snapshot(entries: [DirectoryEntry], total: Int64) -> SpaceSnapshot {
        var map: [String: DirectoryEntry] = [:]
        for entry in entries {
            map[entry.relativePath] = entry
        }
        return SpaceSnapshot(
            selectedPath: "/tmp/example",
            rootPath: "/tmp/example",
            rootResolutionNote: nil,
            breadthWarning: nil,
            capturedAt: fixedDate(1),
            entriesByPath: map,
            issues: [],
            completed: true,
            cancelled: false,
            failureReason: nil,
            totalLogicalBytes: total,
            totalAllocatedBytes: total,
            regularFileCount: entries.count,
            directoryCount: 1,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
    }
}
