import Foundation

public enum ScanPurpose: String, Sendable {
    case baseline
    case rescan
}

public struct SessionActionResult: Equatable, Sendable {
    public var accepted: Bool
    public var message: String?

    public init(accepted: Bool, message: String?) {
        self.accepted = accepted
        self.message = message
    }

    public static func accepted(_ message: String?) -> SessionActionResult {
        SessionActionResult(accepted: true, message: message)
    }

    public static func rejected(_ message: String) -> SessionActionResult {
        SessionActionResult(accepted: false, message: message)
    }
}

public struct MonitorSession: Equatable, Sendable {
    public static let evidenceRetentionLimit = 5000

    public var selectedPath: String?
    public var baseline: SpaceSnapshot?
    public var current: SpaceSnapshot?
    public var diff: SnapshotDiff?
    public var rollups: [ChildRollup]
    public var evidence: [OperationEvidence]
    public var evidenceDroppedCount: Int
    public var processStart: ProcessIOSnapshot?
    public var processLatest: ProcessIOSnapshot?
    public var correlation: ProcessCorrelationResult?
    public var report: AttributionReport
    public var isScanning: Bool
    public var isMonitoring: Bool
    public var needsProcessWindowReset: Bool
    public var lastError: String?
    public var statusMessage: String?
    public var scanIssues: [ScanIssue]
    public var progress: ScanProgress?

    public init() {
        selectedPath = nil
        baseline = nil
        current = nil
        diff = nil
        rollups = []
        evidence = []
        evidenceDroppedCount = 0
        processStart = nil
        processLatest = nil
        correlation = nil
        report = AttributionLimits.makeReport(
            evidenceCount: 0,
            growthPathsOverlappingEvents: 0,
            processCorrelation: nil
        )
        isScanning = false
        isMonitoring = false
        needsProcessWindowReset = false
        lastError = nil
        statusMessage = "尚未选择目录，不会扫描。"
        scanIssues = []
        progress = nil
    }

    public var canEstablishBaseline: Bool { selectedPath != nil && !isScanning }
    public var canRescan: Bool { baseline != nil && !isScanning }
    public var canStartMonitoring: Bool { baseline != nil && !isMonitoring && !isScanning }
    public var canStopMonitoring: Bool { isMonitoring }

    public mutating func selectDirectory(path: String) -> SessionActionResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "没有路径，未扫描。"
            return .rejected(lastError!)
        }
        selectedPath = trimmed
        isMonitoring = false
        isScanning = false
        baseline = nil
        current = nil
        diff = nil
        rollups = []
        evidence = []
        evidenceDroppedCount = 0
        processStart = nil
        processLatest = nil
        correlation = nil
        scanIssues = []
        progress = nil
        needsProcessWindowReset = false
        lastError = nil
        statusMessage = "已选择目录，尚未扫描。建立基线后才会读取该目录。"
        refreshReport()
        return .accepted(statusMessage)
    }

    public mutating func prepareScan(_ purpose: ScanPurpose) -> SessionActionResult {
        guard selectedPath != nil else {
            lastError = "请先选择目录。选择之前不会扫描。"
            return .rejected(lastError!)
        }
        guard !isScanning else {
            lastError = "已有扫描在进行。可以取消后再试。"
            return .rejected(lastError!)
        }
        if purpose == .rescan && baseline == nil {
            lastError = "请先建立基线，再复扫。"
            return .rejected(lastError!)
        }
        isScanning = true
        lastError = nil
        progress = ScanProgress(visited: 0, currentRelativePath: "")
        statusMessage = purpose == .baseline ? "正在建立基线…" : "正在再次扫描…"
        return .accepted(statusMessage)
    }

    public mutating func finishScan(_ snapshot: SpaceSnapshot, purpose: ScanPurpose) -> SessionActionResult {
        guard isScanning else {
            return .rejected("扫描结果已过期，未采用。")
        }
        isScanning = false
        progress = nil
        if snapshot.cancelled || !snapshot.completed {
            let message = snapshot.cancelled
                ? "扫描已取消，基线和当前结果都没有被这次不完整的扫描替换。"
                : (snapshot.failureReason ?? "扫描没有完成，结果未采用。")
            lastError = message
            statusMessage = message
            refreshReport()
            return .rejected(message)
        }

        switch purpose {
        case .baseline:
            let wasMonitoring = isMonitoring
            baseline = snapshot
            current = snapshot
            diff = SnapshotDiff.compare(baseline: snapshot, current: snapshot)
            rollups = ChildRollup.build(baseline: snapshot, current: snapshot)
            evidence = []
            evidenceDroppedCount = 0
            processStart = nil
            processLatest = nil
            correlation = nil
            needsProcessWindowReset = wasMonitoring
            if wasMonitoring {
                statusMessage = "已建立新基线，并清空本窗口的操作证据。监控仍在进行，正在重新采样全进程计数。采样时刻与扫描时刻不同。"
            } else {
                statusMessage = "基线已建立。可以开始监控，或在目录变化后再次扫描。"
            }
        case .rescan:
            guard let baseline else {
                lastError = "没有基线，复扫结果未采用。"
                statusMessage = lastError
                refreshReport()
                return .rejected(lastError!)
            }
            current = snapshot
            diff = SnapshotDiff.compare(baseline: baseline, current: snapshot)
            rollups = ChildRollup.build(baseline: baseline, current: snapshot)
            statusMessage = "复扫完成。逻辑大小差值来自两次扫描，不是进程计数。"
        }

        scanIssues = snapshot.issues
        if !snapshot.issues.isEmpty {
            statusMessage = (statusMessage ?? "") + " 有 \(snapshot.issues.count) 条路径问题，合计不含这些路径。"
        }
        lastError = nil
        refreshReport()
        return .accepted(statusMessage)
    }

    public mutating func validateStartMonitoring() -> SessionActionResult {
        guard baseline != nil else {
            lastError = "请先建立基线，再开始监控。"
            return .rejected(lastError!)
        }
        guard !isScanning else {
            lastError = "扫描仍在进行，暂不能开始监控。"
            return .rejected(lastError!)
        }
        guard !isMonitoring else {
            lastError = "监控已经在进行。"
            return .rejected(lastError!)
        }
        return .accepted(nil)
    }

    public mutating func beginMonitoring(processSample: ProcessIOSnapshot) {
        isMonitoring = true
        processStart = processSample
        processLatest = nil
        correlation = nil
        needsProcessWindowReset = false
        lastError = nil
        if let listError = processSample.listError {
            statusMessage = "监控已开始。\(listError)"
        } else if processSample.obtainableCount == 0 {
            statusMessage = "监控已开始。这次没有获得任何全进程磁盘计数，界面不会把它们显示成 0。"
        } else {
            statusMessage = "监控已开始。FSEvents 没有 PID。全进程计数要等下一次采样才有差值，而且不是此目录的 I/O。"
        }
        refreshReport()
    }

    public mutating func markMonitoringStoppedAwaitingSample() {
        isMonitoring = false
        statusMessage = "监控已停止，正在采样全进程计数…"
    }

    public mutating func stopMonitoring(processSample: ProcessIOSnapshot) {
        isMonitoring = false
        processLatest = processSample
        if let processStart {
            correlation = ProcessIOCorrelation.correlate(from: processStart, to: processSample)
        } else {
            correlation = nil
        }
        needsProcessWindowReset = false
        statusMessage = "监控已停止。若能看到进程差值，那也是全进程计数，不是目标目录的 I/O。"
        if let listError = processSample.listError {
            statusMessage = (statusMessage ?? "") + listError
        }
        refreshReport()
    }

    public mutating func noteProcessSample(_ sample: ProcessIOSnapshot) {
        processLatest = sample
        if let processStart {
            correlation = ProcessIOCorrelation.correlate(from: processStart, to: sample)
        }
        refreshReport()
    }

    public mutating func adoptProcessWindowStart(_ sample: ProcessIOSnapshot) {
        processStart = sample
        processLatest = nil
        correlation = nil
        needsProcessWindowReset = false
        statusMessage = "已用新的全进程计数作为窗口起点。这个时刻不是目录扫描时刻，差值也不是目标目录的 I/O。"
        refreshReport()
    }

    public mutating func appendEvidence(_ item: OperationEvidence) {
        evidence.append(item)
        if evidence.count > Self.evidenceRetentionLimit {
            let overflow = evidence.count - Self.evidenceRetentionLimit
            evidence.removeFirst(overflow)
            evidenceDroppedCount += overflow
        }
        refreshReport()
    }

    public mutating func noteFailure(_ message: String) {
        lastError = message
        statusMessage = message
    }

    private mutating func refreshReport() {
        let overlap: Int
        if let diff {
            overlap = PathOverlap.growthPathsOverlappingEvidence(diff: diff, evidence: evidence)
        } else {
            overlap = 0
        }
        report = AttributionLimits.makeReport(
            evidenceCount: evidence.count,
            growthPathsOverlappingEvents: overlap,
            processCorrelation: correlation
        )
    }
}
