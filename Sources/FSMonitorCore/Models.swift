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

public struct OperationEvidence: Equatable, Sendable, Identifiable {
    public var id: UInt64
    public var observedAt: Date
    public var relativePath: String
    public var flagNames: [String]
    public var rawFlags: UInt32
    public var streamEventID: UInt64?
    public var limitation: String

    public init(
        id: UInt64,
        observedAt: Date,
        relativePath: String,
        flagNames: [String],
        rawFlags: UInt32,
        streamEventID: UInt64?,
        limitation: String
    ) {
        self.id = id
        self.observedAt = observedAt
        self.relativePath = relativePath
        self.flagNames = flagNames
        self.rawFlags = rawFlags
        self.streamEventID = streamEventID
        self.limitation = limitation
    }

    public static func make(
        id: UInt64,
        observedAt: Date,
        relativePath: String,
        rawFlags: UInt32,
        streamEventID: UInt64?
    ) -> OperationEvidence {
        OperationEvidence(
            id: id,
            observedAt: observedAt,
            relativePath: relativePath,
            flagNames: FSEventFlagDecoder.names(for: rawFlags),
            rawFlags: rawFlags,
            streamEventID: streamEventID,
            limitation: FSEventFlagDecoder.noPIDLimitation
        )
    }
}

public struct ProcessIOReading: Equatable, Sendable, Identifiable {
    public var id: String { "\(pid)|\(name)" }
    public var pid: Int32
    public var name: String
    public var wholeProcessBytesRead: UInt64?
    public var wholeProcessBytesWritten: UInt64?
    public var wholeProcessLogicalWrites: UInt64?
    public var unavailableReason: String?

    public init(
        pid: Int32,
        name: String,
        wholeProcessBytesRead: UInt64?,
        wholeProcessBytesWritten: UInt64?,
        wholeProcessLogicalWrites: UInt64?,
        unavailableReason: String?
    ) {
        self.pid = pid
        self.name = name
        self.wholeProcessBytesRead = wholeProcessBytesRead
        self.wholeProcessBytesWritten = wholeProcessBytesWritten
        self.wholeProcessLogicalWrites = wholeProcessLogicalWrites
        self.unavailableReason = unavailableReason
    }
}

public struct ProcessIOSnapshot: Equatable, Sendable {
    public var sampledAt: Date
    public var readings: [ProcessIOReading]
    public var probeNote: String
    public var listError: String?

    public init(sampledAt: Date, readings: [ProcessIOReading], probeNote: String, listError: String?) {
        self.sampledAt = sampledAt
        self.readings = readings
        self.probeNote = probeNote
        self.listError = listError
    }

    public var obtainableCount: Int {
        readings.filter { $0.wholeProcessBytesRead != nil || $0.wholeProcessBytesWritten != nil || $0.wholeProcessLogicalWrites != nil }.count
    }

    public var unavailableCount: Int {
        readings.count - obtainableCount
    }
}

public struct ProcessIODelta: Equatable, Sendable, Identifiable {
    public var id: String { "\(pid)|\(name)" }
    public var pid: Int32
    public var name: String
    public var wholeProcessReadDelta: UInt64?
    public var wholeProcessWriteDelta: UInt64?
    public var wholeProcessLogicalWriteDelta: UInt64?
    public var scopeNote: String

    public init(
        pid: Int32,
        name: String,
        wholeProcessReadDelta: UInt64?,
        wholeProcessWriteDelta: UInt64?,
        wholeProcessLogicalWriteDelta: UInt64?,
        scopeNote: String
    ) {
        self.pid = pid
        self.name = name
        self.wholeProcessReadDelta = wholeProcessReadDelta
        self.wholeProcessWriteDelta = wholeProcessWriteDelta
        self.wholeProcessLogicalWriteDelta = wholeProcessLogicalWriteDelta
        self.scopeNote = scopeNote
    }
}

public struct ProcessCorrelationResult: Equatable, Sendable {
    public var deltas: [ProcessIODelta]
    public var omittedBecauseUnchanged: Int
    public var omittedBecauseUnavailable: Int
    public var omittedBecausePIDReuse: Int
    public var omittedBecauseNewOrExited: Int
    public var truncatedCount: Int

    public init(
        deltas: [ProcessIODelta],
        omittedBecauseUnchanged: Int,
        omittedBecauseUnavailable: Int,
        omittedBecausePIDReuse: Int,
        omittedBecauseNewOrExited: Int,
        truncatedCount: Int
    ) {
        self.deltas = deltas
        self.omittedBecauseUnchanged = omittedBecauseUnchanged
        self.omittedBecauseUnavailable = omittedBecauseUnavailable
        self.omittedBecausePIDReuse = omittedBecausePIDReuse
        self.omittedBecauseNewOrExited = omittedBecauseNewOrExited
        self.truncatedCount = truncatedCount
    }
}

public struct AttributionReport: Equatable, Sendable {
    public var statements: [String]
    public var evidenceCount: Int
    public var growthPathsOverlappingEvents: Int
    public var processCorrelation: ProcessCorrelationResult?
    public var claimsCompletePhysicalAttribution: Bool

    public init(
        statements: [String],
        evidenceCount: Int,
        growthPathsOverlappingEvents: Int,
        processCorrelation: ProcessCorrelationResult?,
        claimsCompletePhysicalAttribution: Bool
    ) {
        self.statements = statements
        self.evidenceCount = evidenceCount
        self.growthPathsOverlappingEvents = growthPathsOverlappingEvents
        self.processCorrelation = processCorrelation
        self.claimsCompletePhysicalAttribution = claimsCompletePhysicalAttribution
    }
}

public enum AttributionLimits {
    public static let statements: [String] = [
        "目录增长来自再次扫描与基线的差异：常规文件的逻辑大小（stat 的 st_size），以及可获得时的已分配块（st_blocks × 512）。硬链接按 inode 只计入合计一次。",
        "FSEvents 只提供路径、事件标志和时间，不提供 PID，不能指出是哪个进程写入。",
        "进程读写只有在 libproc 的 proc_pid_rusage 真实返回时才展示。数值是全进程累计磁盘计数的差值，不是目标目录的 I/O，也不能按路径拆开。",
        "进程采样时刻、目录扫描时刻和 FSEvents 时间接近，只说明时间相关，不是因果关系。",
        "不能声称 100% 物理 IO 归因。压缩、写时复制、稀疏文件、缓存、其他目录上的读写，以及无法读取的路径，都会让这些数字对不上。",
        "默认不需要 root，也不使用 Endpoint Security。本应用没有该项授权，不会把普通权限伪装成已获得 entitlement。调用失败时显示不可获得，不会填 0 或猜测。",
        "应用不会删除文件、不会结束进程、不会关闭 SIP，也不会上传扫描路径或目录内容。只有在你选中目录并建立基线或复扫之后才会读取该目录。"
    ]

    public static func makeReport(
        evidenceCount: Int,
        growthPathsOverlappingEvents: Int,
        processCorrelation: ProcessCorrelationResult?
    ) -> AttributionReport {
        AttributionReport(
            statements: statements,
            evidenceCount: evidenceCount,
            growthPathsOverlappingEvents: growthPathsOverlappingEvents,
            processCorrelation: processCorrelation,
            claimsCompletePhysicalAttribution: false
        )
    }
}
