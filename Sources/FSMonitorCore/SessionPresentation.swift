import Foundation

/// v1.2 presentation helpers driven only by real session flags.
/// Does not invent start/stop sample subtypes when they cannot be distinguished.
public enum PrimaryAction: String, Equatable, Sendable {
    case chooseDirectory
    case establishBaseline
    case startMonitoring
    case rescan
    /// Progress / sample text is the subject; no clickable emphasized primary.
    case none
}

public struct DualTaskStatus: Equatable, Sendable {
    public var monitoringLine: String?
    public var scanningLine: String?
    public var combinedSummary: String

    public init(monitoringLine: String?, scanningLine: String?, combinedSummary: String) {
        self.monitoringLine = monitoringLine
        self.scanningLine = scanningLine
        self.combinedSummary = combinedSummary
    }
}

/// Summary card titles/captions — partial coverage uses Nova v12-addendum-1134 labels.
public struct SummaryCardCopy: Equatable, Sendable {
    public var baselineTitle: String
    public var baselineCaptionHint: String
    public var currentTitle: String
    public var currentCaptionHint: String
    public var deltaTitle: String
    public var deltaCaptionHint: String

    public init(
        baselineTitle: String,
        baselineCaptionHint: String,
        currentTitle: String,
        currentCaptionHint: String,
        deltaTitle: String,
        deltaCaptionHint: String
    ) {
        self.baselineTitle = baselineTitle
        self.baselineCaptionHint = baselineCaptionHint
        self.currentTitle = currentTitle
        self.currentCaptionHint = currentCaptionHint
        self.deltaTitle = deltaTitle
        self.deltaCaptionHint = deltaCaptionHint
    }
}

public enum SessionPresentation {
    /// At most one emphasized next step (spec presentation-v12).
    public static func primaryAction(for session: MonitorSession) -> PrimaryAction {
        if session.selectedPath == nil {
            return .chooseDirectory
        }
        if session.isProcessSamplePending {
            return .none
        }
        if session.isScanning {
            return .none
        }
        if session.baseline == nil {
            return .establishBaseline
        }
        if !session.isMonitoring {
            return .startMonitoring
        }
        return .rescan
    }

    public static func dualTaskStatus(for session: MonitorSession) -> DualTaskStatus {
        let monitoring: String?
        if session.isMonitoring {
            monitoring = "监控：进行中"
        } else if session.isProcessSamplePending {
            // Start vs stop sample cannot be reliably distinguished — keep honest wording.
            monitoring = "监控：采样过渡中"
        } else if session.selectedPath != nil {
            // Idle / never-started / after-stop share one static label — do not claim
            // "已停止" without a dedicated stop feedback path (statusMessage).
            monitoring = "监控：未运行"
        } else {
            monitoring = nil
        }

        let scanning: String?
        if session.isScanning {
            if session.scanCancelRequested {
                scanning = "扫描：取消中"
            } else {
                switch session.activeScanPurpose {
                case .baseline:
                    scanning = "扫描：建立基线中"
                case .rescan:
                    scanning = "扫描：复扫中"
                case nil:
                    scanning = "扫描：进行中"
                }
            }
        } else {
            scanning = "扫描：未进行"
        }

        var parts: [String] = []
        if let monitoring { parts.append(monitoring) }
        if let scanning { parts.append(scanning) }
        // Static dual-task hint (not stop-event copy). Immediate stop feedback stays on statusMessage.
        if session.isScanning, !session.isMonitoring, !session.isProcessSamplePending {
            parts.append("监控未运行，扫描仍在进行")
        }
        return DualTaskStatus(
            monitoringLine: monitoring,
            scanningLine: scanning,
            combinedSummary: parts.joined(separator: " · ")
        )
    }

    // MARK: - Confirmations (Nova v12-addendum-1134 verbatim)

    public static let changeDirectoryConfirmTitle = "更换监控目录？"
    public static let changeDirectoryConfirmMessage =
        "更换后将停止当前监控、取消扫描，并清除本次会话中的基线、对照结果、操作证据和进程读写采样。不会删除磁盘文件。"
    public static let changeDirectoryConfirmAction = "更换目录"

    public static let rebuildBaselineConfirmTitle = "重建基线？"
    public static let rebuildBaselineConfirmMessage =
        "扫描成功后将替换现有基线和对照结果，并清空本次已记录的操作证据。扫描失败或取消会保留旧结果；正在运行的监控不会因此停止。"
    public static let rebuildBaselineConfirmAction = "重建基线"

    /// Rebuild confirms whenever a valid baseline exists. First establish never confirms.
    public static func shouldConfirmRebuildBaseline(for session: MonitorSession) -> Bool {
        session.baseline != nil
    }

    // MARK: - Partial-coverage summary labels

    /// Partial coverage when the accepted diff has coverage gaps or the session still lists scan issues.
    public static func usesPartialCoverageSummaryLabels(
        diff: SnapshotDiff?,
        scanIssues: [ScanIssue]
    ) -> Bool {
        if let diff, diff.coverageGapCount > 0 {
            return true
        }
        return !scanIssues.isEmpty
    }

    public static func summaryCardCopy(partialCoverage: Bool) -> SummaryCardCopy {
        if partialCoverage {
            return SummaryCardCopy(
                baselineTitle: "基线扫描合计",
                baselineCaptionHint: "基线范围；与当前可读不是同一范围，不可直接相减",
                currentTitle: "当前可读合计",
                currentCaptionHint: "可读范围；不可与基线合计直接相减",
                deltaTitle: "可比较逻辑变化",
                deltaCaptionHint: "仅比较两次均可读取的项目，未知项不计入确定增删"
            )
        }
        return SummaryCardCopy(
            baselineTitle: "基线逻辑大小",
            baselineCaptionHint: "目录基线",
            currentTitle: "当前逻辑大小",
            currentCaptionHint: "目录结果",
            deltaTitle: "逻辑增长",
            deltaCaptionHint: "相对基线"
        )
    }

    /// Source-verified clear scope when replacing the selected directory (in-memory only).
    public static let directoryChangeClears: [String] = [
        "基线与当前快照、差异与子项汇总",
        "本窗口操作证据与丢弃计数",
        "进程采样起止与差值",
        "监控/扫描进行中标志与进度",
        "扫描问题列表与陈旧结果标记"
    ]

    /// No on-disk session persistence is implemented; quitting the app does not save history.
    public static let exitRetentionFact =
        "应用退出后不保留监控会话、证据或扫描结果（无本地历史持久化实现）。不得宣称历史已保存。"
}
