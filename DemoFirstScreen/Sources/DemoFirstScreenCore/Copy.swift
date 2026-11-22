import Foundation

public enum DemoCopy {
    public static let comparisonInsufficient = "比较数据不足"
    public static let partialUnknownTotal = "部分读取·完整大小未知"
    public static let activityNotCollected = "活动未采集"
    public static let exampleNotLocal = "示例数据·非本机读取"
    /// Provenance string for the example-interaction source. Kept on the snapshot,
    /// in JSON, and in delivery reports. Albert 05:22: it must not appear in visible UI,
    /// and must not be replaced by a synonymous on-screen badge.
    public static let exampleInteraction = "示例交互·非本机比例"

    public static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        let gb = value / 1_000_000_000.0
        if abs(gb) >= 10 {
            return String(format: "%.0f GB", gb)
        }
        if abs(gb) >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = value / 1_000_000.0
        if abs(mb) >= 1 {
            return String(format: "%.0f MB", mb)
        }
        return "\(bytes) B"
    }
}

/// One atomic on-screen information group. Name, size, time, activity,
/// completeness / unknown, and stale-result identity switch together.
public struct DirectoryInfo: Equatable, Sendable {
    public var id: String?
    public var name: String
    public var sizeBytes: Int64?
    public var sizeText: String
    public var timeText: String
    public var insufficiencyText: String?
    public var activityText: String
    public var staleResultText: String?
    public var identityText: String
    /// On-screen badge text. Nil when the visible identity badge is suppressed
    /// (example-interaction path: the badge is removed; provenance stays in identityText).
    public var onScreenIdentityText: String?
    public var isOverview: Bool

    public init(
        id: String?,
        name: String,
        sizeBytes: Int64?,
        sizeText: String,
        timeText: String,
        insufficiencyText: String?,
        activityText: String,
        staleResultText: String?,
        identityText: String,
        onScreenIdentityText: String? = nil,
        isOverview: Bool
    ) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.sizeText = sizeText
        self.timeText = timeText
        self.insufficiencyText = insufficiencyText
        self.activityText = activityText
        self.staleResultText = staleResultText
        self.identityText = identityText
        self.onScreenIdentityText = onScreenIdentityText
        self.isOverview = isOverview
    }
}

public struct InfoFactory: Equatable, Sendable {
    public var snapshot: DemoSnapshot
    public var chartability: Chartability

    public init(snapshot: DemoSnapshot, chartability: Chartability) {
        self.snapshot = snapshot
        self.chartability = chartability
    }

    public func info(for displayedID: String?) -> DirectoryInfo {
        if let displayedID, let item = snapshot.items.first(where: { $0.id == displayedID }) {
            return itemInfo(item)
        }
        return overviewInfo()
    }

    public func overviewInfo() -> DirectoryInfo {
        // Overview is not a directory list/panel. Example-interaction draws no
        // on-screen identity badge (Albert 05:22). Production insufficiency copy
        // is not drawn on the example preview path.
        let insufficiency: String?
        if snapshot.exampleInteraction {
            insufficiency = nil
        } else {
            insufficiency = DemoCopy.comparisonInsufficient
        }
        return DirectoryInfo(
            id: nil,
            name: "",
            sizeBytes: nil,
            sizeText: "",
            timeText: snapshot.exampleInteraction ? exampleTimeText() : "",
            insufficiencyText: insufficiency,
            activityText: DemoCopy.activityNotCollected,
            staleResultText: nil,
            identityText: identityText(),
            onScreenIdentityText: onScreenIdentityText(),
            isOverview: true
        )
    }

    public func itemInfo(_ item: SnapshotItem) -> DirectoryInfo {
        let sizeText: String
        if let bytes = item.knownBytes {
            sizeText = DemoCopy.formatBytes(bytes)
        } else {
            sizeText = "未知"
        }
        let insufficiency: String?
        if snapshot.exampleInteraction {
            // Example preview: no "比较数据不足" copy. On-screen identity badge is omitted.
            insufficiency = nil
        } else if !chartability.isChartable {
            if item.isPartial {
                insufficiency = "\(DemoCopy.comparisonInsufficient) · \(DemoCopy.partialUnknownTotal)"
            } else {
                insufficiency = DemoCopy.comparisonInsufficient
            }
        } else if item.isPartial {
            insufficiency = DemoCopy.partialUnknownTotal
        } else {
            insufficiency = nil
        }
        return DirectoryInfo(
            id: item.id,
            name: item.name,
            sizeBytes: item.knownBytes,
            sizeText: sizeText,
            timeText: snapshot.exampleInteraction ? exampleTimeText() : timeWindowText(),
            insufficiencyText: insufficiency,
            activityText: DemoCopy.activityNotCollected,
            staleResultText: item.isPartial ? "保留已知值，完整大小未知" : nil,
            identityText: identityText(),
            onScreenIdentityText: onScreenIdentityText(),
            isOverview: false
        )
    }

    public func timeWindowText() -> String {
        let start = Self.timeFormatter.string(from: snapshot.startedAt)
        let end = Self.timeFormatter.string(from: snapshot.endedAt)
        return "采集 \(start)–\(end) PT"
    }

    public func identityText() -> String {
        if snapshot.exampleInteraction {
            return DemoCopy.exampleInteraction
        }
        if snapshot.testOnly {
            return DemoCopy.exampleNotLocal
        }
        return "\(snapshot.label) · \(snapshot.caliberNote)"
    }

    /// Visible UI must not show the example badge or a synonym, and must not
    /// claim local-disk or live-monitoring copy. Internal provenance stays in identityText().
    public func onScreenIdentityText() -> String? {
        if snapshot.exampleInteraction || snapshot.testOnly {
            return nil
        }
        return nil
    }

    public func exampleTimeText() -> String {
        let start = Self.timeFormatter.string(from: snapshot.startedAt)
        return "示例时间 \(start) PT"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
