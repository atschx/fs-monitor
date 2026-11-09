import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

public enum DirectoryScanner {
    public static func scan(
        root: URL,
        cancellation: ScanCancellation,
        now: Date = Date(),
        progressStride: Int = 50,
        progress: ((ScanProgress) -> Void)? = nil
    ) -> SpaceSnapshot {
        let selectedPath = root.standardizedFileURL.path
        if cancellation.isCancelled {
            return failure(
                selectedPath: selectedPath,
                rootPath: selectedPath,
                now: now,
                cancelled: true,
                reason: "扫描已取消。"
            )
        }

        let resolution = resolveRoot(root)
        let rootURL = resolution.url
        let rootPath = rootURL.path
        let warning = PathContainment.breadthWarning(forRootPath: rootPath)

        guard let rootStatus = POSIXStatus.read(path: rootPath) else {
            var snapshot = failure(
                selectedPath: selectedPath,
                rootPath: rootPath,
                now: now,
                cancelled: false,
                reason: "无法读取所选目录：\(rootPath)。"
            )
            snapshot.rootResolutionNote = resolution.note
            snapshot.breadthWarning = warning
            return snapshot
        }
        guard rootStatus.kind == .directory else {
            var snapshot = failure(
                selectedPath: selectedPath,
                rootPath: rootPath,
                now: now,
                cancelled: false,
                reason: "所选路径不是目录。"
            )
            snapshot.rootResolutionNote = resolution.note
            snapshot.breadthWarning = warning
            return snapshot
        }

        var entries: [String: DirectoryEntry] = [:]
        var issues: [ScanIssue] = []
        var seenInodes = Set<InodeKey>()
        var totalLogical: Int64 = 0
        var totalAllocated: Int64 = 0
        var regularFileCount = 0
        var directoryCount = 0
        var symbolicLinkCount = 0
        var hardLinkAliasCount = 0
        var visited = 0
        let stride = max(1, progressStride)
        var cancelled = false

        func record(relativePath: String, status: POSIXStatus) {
            visited += 1
            let entry = makeEntry(
                relativePath: relativePath,
                status: status,
                seenInodes: &seenInodes,
                totalLogical: &totalLogical,
                totalAllocated: &totalAllocated,
                regularFileCount: &regularFileCount,
                directoryCount: &directoryCount,
                symbolicLinkCount: &symbolicLinkCount,
                hardLinkAliasCount: &hardLinkAliasCount
            )
            entries[relativePath] = entry
            if status.kind == .other {
                issues.append(ScanIssue(path: relativePath, message: "非常规文件，未计入大小合计。"))
            }
            if visited == 1 || visited % stride == 0 {
                progress?(ScanProgress(visited: visited, currentRelativePath: relativePath))
            }
        }

        record(
            relativePath: ".",
            status: rootStatus
        )

        var stack: [(url: URL, relative: String)] = [(rootURL, ".")]
        while let current = stack.popLast() {
            if cancellation.isCancelled {
                cancelled = true
                break
            }
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            } catch {
                issues.append(ScanIssue(
                    path: current.relative,
                    message: "无法列出目录：\(error.localizedDescription)"
                ))
                continue
            }

            let ordered = children.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in ordered {
                if cancellation.isCancelled {
                    cancelled = true
                    break
                }
                let name = child.lastPathComponent
                if name == "." || name == ".." || name.isEmpty {
                    continue
                }
                let childPath = child.standardizedFileURL.path
                guard PathContainment.isInside(rootPath: rootPath, candidatePath: childPath),
                      let relative = PathContainment.relative(rootPath: rootPath, candidatePath: childPath),
                      relative != "."
                else {
                    issues.append(ScanIssue(path: childPath, message: "路径超出所选目录，已跳过。"))
                    continue
                }
                guard let status = POSIXStatus.read(path: childPath) else {
                    issues.append(ScanIssue(path: relative, message: "无法读取文件状态。"))
                    continue
                }
                record(relativePath: relative, status: status)
                if status.kind == .directory {
                    if status.device != rootStatus.device {
                        issues.append(ScanIssue(path: relative, message: "位于其他挂载点，未进入。"))
                    } else {
                        stack.append((URL(fileURLWithPath: childPath), relative))
                    }
                }
            }
            if cancelled {
                break
            }
        }

        if cancelled {
            progress?(ScanProgress(visited: visited, currentRelativePath: ""))
            return SpaceSnapshot(
                selectedPath: selectedPath,
                rootPath: rootPath,
                rootResolutionNote: resolution.note,
                breadthWarning: warning,
                capturedAt: now,
                entriesByPath: entries,
                issues: issues,
                completed: false,
                cancelled: true,
                failureReason: "扫描已取消。",
                totalLogicalBytes: totalLogical,
                totalAllocatedBytes: totalAllocated,
                regularFileCount: regularFileCount,
                directoryCount: directoryCount,
                symbolicLinkCount: symbolicLinkCount,
                hardLinkAliasCount: hardLinkAliasCount
            )
        }

        return SpaceSnapshot(
            selectedPath: selectedPath,
            rootPath: rootPath,
            rootResolutionNote: resolution.note,
            breadthWarning: warning,
            capturedAt: now,
            entriesByPath: entries,
            issues: issues,
            completed: true,
            cancelled: false,
            failureReason: nil,
            totalLogicalBytes: totalLogical,
            totalAllocatedBytes: totalAllocated,
            regularFileCount: regularFileCount,
            directoryCount: directoryCount,
            symbolicLinkCount: symbolicLinkCount,
            hardLinkAliasCount: hardLinkAliasCount
        )
    }

    private static func resolveRoot(_ root: URL) -> (url: URL, note: String?) {
        let selected = root.standardizedFileURL
        if let status = POSIXStatus.read(path: selected.path), status.kind == .symbolicLink {
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL
            return (resolved, "所选路径是符号链接，实际扫描 \(resolved.path)。")
        }
        return (selected, nil)
    }

    private static func failure(
        selectedPath: String,
        rootPath: String,
        now: Date,
        cancelled: Bool,
        reason: String
    ) -> SpaceSnapshot {
        SpaceSnapshot(
            selectedPath: selectedPath,
            rootPath: rootPath,
            rootResolutionNote: nil,
            breadthWarning: nil,
            capturedAt: now,
            entriesByPath: [:],
            issues: cancelled ? [] : [ScanIssue(path: rootPath, message: reason)],
            completed: false,
            cancelled: cancelled,
            failureReason: reason,
            totalLogicalBytes: 0,
            totalAllocatedBytes: 0,
            regularFileCount: 0,
            directoryCount: 0,
            symbolicLinkCount: 0,
            hardLinkAliasCount: 0
        )
    }

    private static func makeEntry(
        relativePath: String,
        status: POSIXStatus,
        seenInodes: inout Set<InodeKey>,
        totalLogical: inout Int64,
        totalAllocated: inout Int64,
        regularFileCount: inout Int,
        directoryCount: inout Int,
        symbolicLinkCount: inout Int,
        hardLinkAliasCount: inout Int
    ) -> DirectoryEntry {
        switch status.kind {
        case .directory:
            directoryCount += 1
        case .symbolicLink:
            symbolicLinkCount += 1
        case .regularFile:
            regularFileCount += 1
        case .other:
            break
        }

        var counts = false
        var note: String?
        if status.kind == .regularFile {
            let key = InodeKey(device: status.device, inode: status.inode)
            if seenInodes.contains(key) {
                hardLinkAliasCount += 1
                note = "硬链接，逻辑大小已在同一 inode 的首次路径计入合计。"
            } else {
                seenInodes.insert(key)
                counts = true
                totalLogical += status.logicalSize
                totalAllocated += status.allocatedSize ?? 0
            }
        }

        let logical: Int64 = status.kind == .regularFile ? status.logicalSize : 0
        let allocated: Int64? = status.kind == .regularFile ? status.allocatedSize : nil
        return DirectoryEntry(
            relativePath: relativePath,
            kind: status.kind,
            logicalSize: logical,
            allocatedSize: allocated,
            modifiedAt: status.modifiedAt,
            device: status.device,
            inode: status.inode,
            countsTowardTotal: counts,
            hardLinkNote: note
        )
    }
}

private struct InodeKey: Hashable {
    var device: UInt64
    var inode: UInt64
}

private struct POSIXStatus {
    var kind: EntryKind
    var logicalSize: Int64
    var allocatedSize: Int64?
    var modifiedAt: Date?
    var device: UInt64
    var inode: UInt64

    static func read(path: String) -> POSIXStatus? {
        path.withCString { pointer in
            status(at: pointer)
        }
    }

    private static func status(at pointer: UnsafePointer<CChar>) -> POSIXStatus? {
        var info = stat()
        guard lstat(pointer, &info) == 0 else { return nil }
        return POSIXStatus(
            kind: kind(of: info.st_mode),
            logicalSize: Int64(info.st_size),
            allocatedSize: Int64(info.st_blocks) * 512,
            modifiedAt: modificationDate(info),
            device: UInt64(truncatingIfNeeded: info.st_dev),
            inode: UInt64(truncatingIfNeeded: info.st_ino)
        )
    }

    private static func kind(of mode: mode_t) -> EntryKind {
        let raw = UInt32(mode)
        let type = raw & UInt32(truncatingIfNeeded: S_IFMT)
        if type == UInt32(truncatingIfNeeded: S_IFREG) { return .regularFile }
        if type == UInt32(truncatingIfNeeded: S_IFDIR) { return .directory }
        if type == UInt32(truncatingIfNeeded: S_IFLNK) { return .symbolicLink }
        return .other
    }

    private static func modificationDate(_ info: stat) -> Date {
        #if os(macOS)
        let seconds = info.st_mtimespec.tv_sec
        let nanoseconds = info.st_mtimespec.tv_nsec
        #else
        let seconds = info.st_mtim.tv_sec
        let nanoseconds = info.st_mtim.tv_nsec
        #endif
        return Date(
            timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000
        )
    }
}
