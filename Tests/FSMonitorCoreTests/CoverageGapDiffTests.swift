import Foundation
import XCTest
@testable import FSMonitorCore

final class CoverageGapDiffTests: XCTestCase {
    func testCurrentUnreadPathIsCoverageGapNotRemoved() {
        let hidden = entry("secret/hidden.txt", size: 100)
        let visible = entry("visible.txt", size: 40)
        let baseline = snapshot(
            entries: [hidden, visible, directory("secret")],
            total: 140,
            issues: []
        )
        let current = snapshot(
            entries: [visible, directory("secret")],
            total: 40,
            issues: [ScanIssue(path: "secret", message: "无法列出目录：Permission denied")]
        )

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["secret/hidden.txt"]?.change, .coverageGap)
        XCTAssertEqual(byPath["secret/hidden.txt"]?.logicalDelta, 0)
        XCTAssertEqual(diff.removedCount, 0)
        XCTAssertEqual(diff.coverageGapCount, 1)
        XCTAssertEqual(diff.logicalDelta, 0)
        XCTAssertEqual(diff.allocatedDelta, 0)

        let rollups = Dictionary(
            uniqueKeysWithValues: ChildRollup.build(baseline: baseline, current: current)
                .map { ($0.relativePath, $0) }
        )
        // Uncovered secret/hidden must not appear as a shrink under secret.
        XCTAssertEqual(rollups["secret"]?.logicalDelta ?? 0, 0)
        XCTAssertEqual(rollups["visible.txt"]?.logicalDelta, 0)
    }

    func testBaselineCoverageGapIsNotConfidentAdd() {
        let revealed = entry("secret/hidden.txt", size: 80)
        let visible = entry("visible.txt", size: 20)
        let baseline = snapshot(
            entries: [visible, directory("secret")],
            total: 20,
            issues: [ScanIssue(path: "secret", message: "无法列出目录：Permission denied")]
        )
        let current = snapshot(
            entries: [visible, revealed, directory("secret")],
            total: 100,
            issues: []
        )

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["secret/hidden.txt"]?.change, .coverageGap)
        XCTAssertEqual(byPath["secret/hidden.txt"]?.logicalDelta, 0)
        XCTAssertEqual(diff.addedCount, 0)
        XCTAssertEqual(diff.coverageGapCount, 1)
        XCTAssertEqual(diff.logicalDelta, 0)
    }

    func testUnreadFileStatusIsCoverageGapNotRemoved() {
        let blocked = entry("blocked.bin", size: 64)
        let keep = entry("keep.txt", size: 8)
        let baseline = snapshot(entries: [blocked, keep], total: 72, issues: [])
        let current = snapshot(
            entries: [keep],
            total: 8,
            issues: [ScanIssue(path: "blocked.bin", message: "无法读取文件状态。")]
        )

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["blocked.bin"]?.change, .coverageGap)
        XCTAssertEqual(byPath["keep.txt"]?.change, .unchanged)
        XCTAssertEqual(diff.removedCount, 0)
        XCTAssertEqual(diff.logicalDelta, 0)
    }

    func testBothReadableTrueDeleteRemainsRemoved() {
        let gone = entry("gone.txt", size: 50)
        let keep = entry("keep.txt", size: 10)
        let baseline = snapshot(entries: [gone, keep], total: 60, issues: [])
        let current = snapshot(entries: [keep], total: 10, issues: [])

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["gone.txt"]?.change, .removed)
        XCTAssertEqual(byPath["gone.txt"]?.logicalDelta, -50)
        XCTAssertEqual(diff.removedCount, 1)
        XCTAssertEqual(diff.coverageGapCount, 0)
        XCTAssertEqual(diff.logicalDelta, -50)
    }

    func testBothReadableTrueAddRemainsAdded() {
        let keep = entry("keep.txt", size: 10)
        let neu = entry("new.txt", size: 30)
        let baseline = snapshot(entries: [keep], total: 10, issues: [])
        let current = snapshot(entries: [keep, neu], total: 40, issues: [])

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["new.txt"]?.change, .added)
        XCTAssertEqual(diff.addedCount, 1)
        XCTAssertEqual(diff.coverageGapCount, 0)
        XCTAssertEqual(diff.logicalDelta, 30)
    }

    func testCoverageGapDoesNotMaskSiblingTrueDelete() {
        let hidden = entry("secret/hidden.txt", size: 100)
        let gone = entry("gone.txt", size: 25)
        let keep = entry("keep.txt", size: 5)
        let baseline = snapshot(
            entries: [hidden, gone, keep, directory("secret")],
            total: 130,
            issues: []
        )
        let current = snapshot(
            entries: [keep, directory("secret")],
            total: 5,
            issues: [ScanIssue(path: "secret", message: "无法列出目录：Permission denied")]
        )

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["secret/hidden.txt"]?.change, .coverageGap)
        XCTAssertEqual(byPath["gone.txt"]?.change, .removed)
        XCTAssertEqual(diff.removedCount, 1)
        XCTAssertEqual(diff.coverageGapCount, 1)
        // Aggregate reflects only the confident delete of gone.txt (25), not the unread 100.
        XCTAssertEqual(diff.logicalDelta, -25)
    }

    func testSkippedMountDescendantsAreCoverageGaps() {
        let nested = entry("mnt/nested.bin", size: 200)
        let keep = entry("keep.txt", size: 4)
        let baseline = snapshot(
            entries: [nested, keep, directory("mnt")],
            total: 204,
            issues: []
        )
        let current = snapshot(
            entries: [keep, directory("mnt")],
            total: 4,
            issues: [ScanIssue(path: "mnt", message: "位于其他挂载点，未进入。")]
        )

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: diff.changes.map { ($0.relativePath, $0) })

        XCTAssertEqual(byPath["mnt/nested.bin"]?.change, .coverageGap)
        XCTAssertEqual(diff.removedCount, 0)
        XCTAssertEqual(diff.logicalDelta, 0)
    }

    func testUnreadableDirectoryIntegrationDoesNotReportHiddenAsRemoved() throws {
        let root = try makeTempDirectory()
        defer {
            chmod(root.appendingPathComponent("secret").path, 0o755)
            removeTempDirectory(root)
        }
        let secret = root.appendingPathComponent("secret", isDirectory: true)
        let hiddenSize = try writeMarkedFile(at: secret.appendingPathComponent("hidden.txt"), extraBytes: 8)
        let visibleSize = try writeMarkedFile(at: root.appendingPathComponent("visible.txt"), extraBytes: 4)
        let baseline = DirectoryScanner.scan(root: root, cancellation: ScanCancellation(), now: fixedDate(1))
        XCTAssertEqual(baseline.entriesByPath["secret/hidden.txt"]?.logicalSize, Int64(hiddenSize))

        XCTAssertEqual(chmod(secret.path, 0), 0)
        let current = DirectoryScanner.scan(root: root, cancellation: ScanCancellation(), now: fixedDate(2))
        XCTAssertNil(current.entriesByPath["secret/hidden.txt"])
        XCTAssertFalse(current.issues.isEmpty)

        let diff = SnapshotDiff.compare(baseline: baseline, current: current)
        let hiddenChange = diff.changes.first { $0.relativePath == "secret/hidden.txt" }
        XCTAssertEqual(hiddenChange?.change, .coverageGap)
        XCTAssertEqual(diff.removedCount, 0)
        XCTAssertEqual(diff.logicalDelta, 0)
        XCTAssertEqual(current.totalLogicalBytes, Int64(visibleSize))
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

    private func directory(_ path: String) -> DirectoryEntry {
        DirectoryEntry(
            relativePath: path,
            kind: .directory,
            logicalSize: 0,
            allocatedSize: 0,
            modifiedAt: nil,
            device: 1,
            inode: UInt64(path.utf8.reduce(UInt64(10_000)) { $0 + UInt64($1) }),
            countsTowardTotal: false,
            hardLinkNote: nil
        )
    }

    private func snapshot(
        entries: [DirectoryEntry],
        total: Int64,
        issues: [ScanIssue]
    ) -> SpaceSnapshot {
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
            issues: issues,
            completed: true,
            cancelled: false,
            failureReason: nil,
            totalLogicalBytes: total,
            totalAllocatedBytes: total,
            regularFileCount: entries.filter { $0.kind == .regularFile }.count,
            directoryCount: entries.filter { $0.kind == .directory }.count + 1,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
    }
}
