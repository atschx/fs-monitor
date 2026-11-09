import Foundation
import XCTest
@testable import FSMonitorCore

final class ScannerTests: XCTestCase {
    func testScanSumsRegularFilesAndSkipsDirectoryMetadata() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        let fileA = try writeMarkedFile(at: root.appendingPathComponent("a.txt"), extraBytes: 10)
        let fileB = try writeMarkedFile(at: root.appendingPathComponent("nested/b.txt"), extraBytes: 25)
        XCTAssertTrue(TestDataMark.banner.contains("【测试数据】"))

        let snapshot = DirectoryScanner.scan(root: root, cancellation: ScanCancellation(), now: fixedDate(10))

        XCTAssertTrue(snapshot.completed)
        XCTAssertFalse(snapshot.cancelled)
        XCTAssertEqual(snapshot.totalLogicalBytes, Int64(fileA + fileB))
        XCTAssertEqual(snapshot.regularFileCount, 2)
        XCTAssertGreaterThanOrEqual(snapshot.directoryCount, 2)
        XCTAssertEqual(snapshot.entriesByPath["a.txt"]?.logicalSize, Int64(fileA))
        XCTAssertEqual(snapshot.entriesByPath["nested/b.txt"]?.countsTowardTotal, true)
        XCTAssertEqual(snapshot.entriesByPath["."]?.logicalSize, 0)
        XCTAssertEqual(snapshot.entriesByPath["nested"]?.logicalSize, 0)
        XCTAssertNil(snapshot.breadthWarning)
    }

    func testHardLinkIsCountedOnce() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        let original = root.appendingPathComponent("original.txt")
        let size = try writeMarkedFile(at: original, extraBytes: 40)
        let alias = root.appendingPathComponent("alias.txt")
        try FileManager.default.linkItem(at: original, to: alias)

        let snapshot = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())

        XCTAssertEqual(snapshot.totalLogicalBytes, Int64(size))
        XCTAssertEqual(snapshot.hardLinkAliasCount, 1)
        let counted = snapshot.entriesByPath.values.filter(\.countsTowardTotal)
        XCTAssertEqual(counted.count, 1)
        let notes = [
            snapshot.entriesByPath["alias.txt"]?.hardLinkNote,
            snapshot.entriesByPath["original.txt"]?.hardLinkNote
        ].compactMap { $0 }
        XCTAssertEqual(notes.count, 1)

        let extra = Data("more".utf8)
        let bigger = try Data(contentsOf: original) + extra
        try bigger.write(to: original)
        let grown = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())
        let diff = SnapshotDiff.compare(baseline: snapshot, current: grown)
        let rowSum = diff.changes
            .filter { $0.relativePath == "alias.txt" || $0.relativePath == "original.txt" }
            .reduce(Int64(0)) { $0 + $1.logicalDelta }
        XCTAssertEqual(diff.logicalDelta, Int64(extra.count))
        XCTAssertEqual(rowSum, Int64(extra.count) * 2)
    }

    func testSymbolicLinkDoesNotPullOutsideContent() throws {
        let parent = try makeTempDirectory()
        defer { removeTempDirectory(parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outsideSize = try writeMarkedFile(at: outside.appendingPathComponent("big.bin"), extraBytes: 50_000)
        XCTAssertGreaterThan(outsideSize, 10_000)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let snapshot = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())

        XCTAssertTrue(snapshot.completed)
        XCTAssertEqual(snapshot.totalLogicalBytes, 0)
        XCTAssertEqual(snapshot.symbolicLinkCount, 1)
        XCTAssertNil(snapshot.entriesByPath["escape/big.bin"])
        XCTAssertFalse(snapshot.entriesByPath.keys.contains { $0.contains("outside") })
    }

    func testUnreadableDirectoryIsAnIssueAndScanStillCompletes() throws {
        let root = try makeTempDirectory()
        defer {
            chmod(root.appendingPathComponent("secret").path, 0o755)
            removeTempDirectory(root)
        }
        let secret = root.appendingPathComponent("secret", isDirectory: true)
        _ = try writeMarkedFile(at: secret.appendingPathComponent("hidden.txt"), extraBytes: 8)
        XCTAssertEqual(chmod(secret.path, 0), 0)

        let snapshot = DirectoryScanner.scan(root: root, cancellation: ScanCancellation())

        XCTAssertTrue(snapshot.completed)
        XCTAssertNil(snapshot.entriesByPath["secret/hidden.txt"])
        XCTAssertFalse(snapshot.issues.isEmpty)
        XCTAssertEqual(snapshot.totalLogicalBytes, 0)
    }

    func testCancellationStopsBeforeCompletion() throws {
        let root = try makeTempDirectory()
        defer { removeTempDirectory(root) }
        for index in 0..<30 {
            _ = try writeMarkedFile(at: root.appendingPathComponent("file-\(index).txt"), extraBytes: 1)
        }
        let cancellation = ScanCancellation()
        let snapshot = DirectoryScanner.scan(
            root: root,
            cancellation: cancellation,
            progressStride: 1
        ) { _ in
            cancellation.cancel()
        }

        XCTAssertTrue(snapshot.cancelled)
        XCTAssertFalse(snapshot.completed)
        XCTAssertLessThan(snapshot.entriesByPath.count, 31)
    }

    func testAlreadyCancelledScanDoesNotReportMissingPath() {
        let cancellation = ScanCancellation()
        cancellation.cancel()
        let missing = URL(fileURLWithPath: "/tmp/fs-monitor-does-not-exist-\(UUID().uuidString)")
        let snapshot = DirectoryScanner.scan(root: missing, cancellation: cancellation)
        XCTAssertTrue(snapshot.cancelled)
        XCTAssertFalse(snapshot.completed)
        XCTAssertEqual(snapshot.failureReason, "扫描已取消。")
        XCTAssertTrue(snapshot.entriesByPath.isEmpty)
    }

    func testMissingPathFailsWithoutBecomingEmptyBaseline() {
        let missing = URL(fileURLWithPath: "/tmp/fs-monitor-missing-\(UUID().uuidString)")
        let snapshot = DirectoryScanner.scan(root: missing, cancellation: ScanCancellation())
        XCTAssertFalse(snapshot.completed)
        XCTAssertFalse(snapshot.cancelled)
        XCTAssertNotNil(snapshot.failureReason)
        XCTAssertTrue(snapshot.failureReason?.contains("无法读取") == true)
    }

    func testBreadthWarningOnlyForVeryWideRoots() {
        XCTAssertNotNil(PathContainment.breadthWarning(forRootPath: "/"))
        XCTAssertNotNil(PathContainment.breadthWarning(forRootPath: "/Users"))
        XCTAssertNil(PathContainment.breadthWarning(forRootPath: "/tmp/fs-monitor-demo"))
    }
}
