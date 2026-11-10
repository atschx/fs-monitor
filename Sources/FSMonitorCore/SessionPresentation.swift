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
        } else if session.baseline != nil {
            monitoring = "监控：已停止"
        } else if session.selectedPath != nil {
            monitoring = "监控：未开始"
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
        if session.isScanning, !session.isMonitoring, session.baseline != nil {
            parts.append("监控已停止，扫描继续")
        }
        return DualTaskStatus(
            monitoringLine: monitoring,
            scanningLine: scanning,
            combinedSummary: parts.joined(separator: " · ")
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
