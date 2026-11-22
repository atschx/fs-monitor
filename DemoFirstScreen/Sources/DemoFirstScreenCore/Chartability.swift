import Foundation

/// A sector that may be drawn only after the completeness / non-overlap gate passes.
public struct ChartSector: Equatable, Sendable {
    public var id: String
    public var name: String
    public var bytes: Int64
    public var startDegrees: Double
    public var endDegrees: Double

    public var sweepDegrees: Double { endDegrees - startDegrees }

    public init(id: String, name: String, bytes: Int64, startDegrees: Double, endDegrees: Double) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.startDegrees = startDegrees
        self.endDegrees = endDegrees
    }
}

public enum Chartability: Equatable, Sendable {
    /// Production Eric du snapshot lands here: values may still be shown, but no proportion chart.
    case insufficient(reason: String)
    case chartable(sectors: [ChartSector], denominator: Int64)

    public var sectors: [ChartSector] {
        switch self {
        case .insufficient: return []
        case .chartable(let sectors, _): return sectors
        }
    }

    public var isChartable: Bool {
        if case .chartable = self { return true }
        return false
    }
}

public enum ChartabilityGate {
    public static let maxSectors = 5
    public static let semicircleDegrees = 180.0
    public static let startDegrees = 180.0
    public static let endDegrees = 360.0

    /// Chart only when every included item is the same caliber, a complete success,
    /// and the snapshot has verified non-overlap (including APFS root/Data alias dedup).
    /// Angle = item.bytes / sum(included) * 180. Unknown/partial items are not treated as 0
    /// and cannot enter the denominator.
    public static func evaluate(_ snapshot: DemoSnapshot) -> Chartability {
        if snapshot.testOnly && snapshot.exampleInteraction {
            return .insufficient(reason: "示例交互与 testOnly 夹具不得混用")
        }
        if snapshot.items.isEmpty {
            return .insufficient(reason: "没有可比较的目录项")
        }
        // Real production snapshots stay un-chartable unless overlap was actually verified.
        // The independent example-interaction source may chart its own declared example values
        // (never the Eric du bytes). testOnly fixtures keep the existing verification gate.
        if let proof=snapshot.folderLogicalProof {
            guard snapshot.caliber == .logical,!snapshot.exampleInteraction,!snapshot.testOnly,
                  !snapshot.apfsRootDataDedupVerified,snapshot.nonOverlapVerified,
                  proof.snapshotID==snapshot.id,!proof.rootPath.isEmpty,proof.complete,proof.stableDeviceInodeOwnership,
                  snapshot.items.allSatisfy({$0.readStatus == .reportedComplete && $0.errorCount==0 && $0.knownBytes != nil}) else {
                return .insufficient(reason:"文件夹 logical 同源完整与唯一归桶未证；物理/APFS门禁不适用")
            }
            var total:Int64=0
            for item in snapshot.items {let (n,overflow)=total.addingReportingOverflow(item.knownBytes!);guard !overflow else{return .insufficient(reason:"合计溢出")};total=n}
            guard total==proof.bucketTotal else{return .insufficient(reason:"同源桶合计不一致")}
        } else if !snapshot.exampleInteraction {
            if !snapshot.nonOverlapVerified || !snapshot.apfsRootDataDedupVerified {
                return .insufficient(reason: "完整且不重叠范围未证，不得图化")
            }
        }

        var included: [SnapshotItem] = []
        for item in snapshot.items {
            if item.readStatus != .reportedComplete || item.errorCount != 0 {
                continue
            }
            guard let bytes = item.knownBytes else { continue }
            if snapshot.folderLogicalProof != nil && bytes==0 {continue}
            included.append(SnapshotItem(id: item.id, name: item.name, bytes: bytes, errorCount: item.errorCount, readStatus: item.readStatus))
        }

        if included.isEmpty {
            return .insufficient(reason: "没有同口径完整成功且不重叠的已核项")
        }
        if included.count > maxSectors {
            return .insufficient(reason: "可图化扇区超过最多 5 项")
        }

        let denominator = included.reduce(Int64(0)) { $0 + ($1.knownBytes ?? 0) }
        if denominator <= 0 {
            return .insufficient(reason: "完整成功项合计不可用（未知不得当 0 求和）")
        }

        var cursor = startDegrees
        var sectors: [ChartSector] = []
        for (index, item) in included.enumerated() {
            let bytes = item.knownBytes!
            let isLast = index == included.count - 1
            let end: Double
            if isLast {
                end = endDegrees
            } else {
                end = cursor + (Double(bytes) / Double(denominator)) * semicircleDegrees
            }
            sectors.append(
                ChartSector(id: item.id, name: item.name, bytes: bytes, startDegrees: cursor, endDegrees: end)
            )
            cursor = end
        }
        return .chartable(sectors: sectors, denominator: denominator)
    }
}
