import Foundation

public enum EntryKind: String, Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other

    public var label: String {
        switch self {
        case .regularFile: return "文件"
        case .directory: return "目录"
        case .symbolicLink: return "符号链接"
        case .other: return "其他"
        }
    }
}

public struct DirectoryEntry: Equatable, Sendable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var kind: EntryKind
    public var logicalSize: Int64
    public var allocatedSize: Int64?
    public var modifiedAt: Date?
    public var device: UInt64
    public var inode: UInt64
    public var countsTowardTotal: Bool
    public var hardLinkNote: String?

    public init(
        relativePath: String,
        kind: EntryKind,
        logicalSize: Int64,
        allocatedSize: Int64?,
        modifiedAt: Date?,
        device: UInt64,
        inode: UInt64,
        countsTowardTotal: Bool,
        hardLinkNote: String?
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.modifiedAt = modifiedAt
        self.device = device
        self.inode = inode
        self.countsTowardTotal = countsTowardTotal
        self.hardLinkNote = hardLinkNote
    }
}

public struct ScanIssue: Equatable, Sendable, Identifiable {
    public var id: String { "\(path)|\(message)" }
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct ScanProgress: Equatable, Sendable {
    public var visited: Int
    public var currentRelativePath: String

    public init(visited: Int, currentRelativePath: String) {
        self.visited = visited
        self.currentRelativePath = currentRelativePath
    }
}

public struct SpaceSnapshot: Equatable, Sendable {
    public var selectedPath: String
    public var rootPath: String
    public var rootResolutionNote: String?
    public var breadthWarning: String?
    public var capturedAt: Date
    public var entriesByPath: [String: DirectoryEntry]
    public var issues: [ScanIssue]
    public var completed: Bool
    public var cancelled: Bool
    public var failureReason: String?
    public var totalLogicalBytes: Int64
    public var totalAllocatedBytes: Int64
    public var regularFileCount: Int
    public var directoryCount: Int
    public var symbolicLinkCount: Int
    public var hardLinkAliasCount: Int

    public init(
        selectedPath: String,
        rootPath: String,
        rootResolutionNote: String?,
        breadthWarning: String?,
        capturedAt: Date,
        entriesByPath: [String: DirectoryEntry],
        issues: [ScanIssue],
        completed: Bool,
        cancelled: Bool,
        failureReason: String?,
        totalLogicalBytes: Int64,
        totalAllocatedBytes: Int64,
        regularFileCount: Int,
        directoryCount: Int,
        symbolicLinkCount: Int,
        hardLinkAliasCount: Int
    ) {
        self.selectedPath = selectedPath
        self.rootPath = rootPath
        self.rootResolutionNote = rootResolutionNote
        self.breadthWarning = breadthWarning
        self.capturedAt = capturedAt
        self.entriesByPath = entriesByPath
        self.issues = issues
        self.completed = completed
        self.cancelled = cancelled
        self.failureReason = failureReason
        self.totalLogicalBytes = totalLogicalBytes
        self.totalAllocatedBytes = totalAllocatedBytes
        self.regularFileCount = regularFileCount
        self.directoryCount = directoryCount
        self.symbolicLinkCount = symbolicLinkCount
        self.hardLinkAliasCount = hardLinkAliasCount
    }

    public var entriesSorted: [DirectoryEntry] {
        entriesByPath.values.sorted { $0.relativePath < $1.relativePath }
    }
}
