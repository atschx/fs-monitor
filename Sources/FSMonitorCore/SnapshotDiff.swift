import Foundation

public enum ChangeKind: String, Equatable, Sendable {
    case added
    case removed
    case grown
    case shrunk
    case unchanged
    case typeChanged

    public var label: String {
        switch self {
        case .added: return "新增"
        case .removed: return "删除"
        case .grown: return "增长"
        case .shrunk: return "缩小"
        case .unchanged: return "未变化"
        case .typeChanged: return "类型变化"
        }
    }
}

public struct EntryChange: Equatable, Sendable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var change: ChangeKind
    public var baselineLogical: Int64
    public var currentLogical: Int64
    public var logicalDelta: Int64
    public var baselineAllocated: Int64?
    public var currentAllocated: Int64?
    public var kind: EntryKind
    public var countsTowardTotal: Bool
    public var note: String?

    public init(
        relativePath: String,
        change: ChangeKind,
        baselineLogical: Int64,
        currentLogical: Int64,
        logicalDelta: Int64,
        baselineAllocated: Int64?,
        currentAllocated: Int64?,
        kind: EntryKind,
        countsTowardTotal: Bool,
        note: String?
    ) {
        self.relativePath = relativePath
        self.change = change
        self.baselineLogical = baselineLogical
        self.currentLogical = currentLogical
        self.logicalDelta = logicalDelta
        self.baselineAllocated = baselineAllocated
        self.currentAllocated = currentAllocated
        self.kind = kind
        self.countsTowardTotal = countsTowardTotal
        self.note = note
    }
}

public struct SnapshotDiff: Equatable, Sendable {
    public var changes: [EntryChange]
    public var logicalDelta: Int64
    public var allocatedDelta: Int64
    public var addedCount: Int
    public var removedCount: Int
    public var grownCount: Int
    public var shrunkCount: Int
    public var typeChangedCount: Int
    public var unchangedCount: Int

    public init(
        changes: [EntryChange],
        logicalDelta: Int64,
        allocatedDelta: Int64,
        addedCount: Int,
        removedCount: Int,
        grownCount: Int,
        shrunkCount: Int,
        typeChangedCount: Int,
        unchangedCount: Int
    ) {
        self.changes = changes
        self.logicalDelta = logicalDelta
        self.allocatedDelta = allocatedDelta
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.grownCount = grownCount
        self.shrunkCount = shrunkCount
        self.typeChangedCount = typeChangedCount
        self.unchangedCount = unchangedCount
    }

    public static func compare(baseline: SpaceSnapshot, current: SpaceSnapshot) -> SnapshotDiff {
        let paths = Set(baseline.entriesByPath.keys).union(current.entriesByPath.keys)
        var changes: [EntryChange] = []
        changes.reserveCapacity(paths.count)
        for path in paths where path != "." {
            guard let change = makeChange(
                path: path,
                baseline: baseline.entriesByPath[path],
                current: current.entriesByPath[path]
            ) else { continue }
            changes.append(change)
        }
        changes.sort { $0.relativePath < $1.relativePath }
        return SnapshotDiff(
            changes: changes,
            logicalDelta: current.totalLogicalBytes - baseline.totalLogicalBytes,
            allocatedDelta: current.totalAllocatedBytes - baseline.totalAllocatedBytes,
            addedCount: changes.filter { $0.change == .added }.count,
            removedCount: changes.filter { $0.change == .removed }.count,
            grownCount: changes.filter { $0.change == .grown }.count,
            shrunkCount: changes.filter { $0.change == .shrunk }.count,
            typeChangedCount: changes.filter { $0.change == .typeChanged }.count,
            unchangedCount: changes.filter { $0.change == .unchanged }.count
        )
    }

    private static func makeChange(path: String, baseline: DirectoryEntry?, current: DirectoryEntry?) -> EntryChange? {
        switch (baseline, current) {
        case let (old?, new?):
            let delta = new.logicalSize - old.logicalSize
            let kind: ChangeKind
            if old.kind != new.kind {
                kind = .typeChanged
            } else if delta > 0 {
                kind = .grown
            } else if delta < 0 {
                kind = .shrunk
            } else {
                kind = .unchanged
            }
            return EntryChange(
                relativePath: path,
                change: kind,
                baselineLogical: old.logicalSize,
                currentLogical: new.logicalSize,
                logicalDelta: delta,
                baselineAllocated: old.allocatedSize,
                currentAllocated: new.allocatedSize,
                kind: new.kind,
                countsTowardTotal: new.countsTowardTotal,
                note: new.hardLinkNote ?? old.hardLinkNote
            )
        case let (old?, nil):
            return EntryChange(
                relativePath: path,
                change: .removed,
                baselineLogical: old.logicalSize,
                currentLogical: 0,
                logicalDelta: -old.logicalSize,
                baselineAllocated: old.allocatedSize,
                currentAllocated: nil,
                kind: old.kind,
                countsTowardTotal: old.countsTowardTotal,
                note: old.hardLinkNote
            )
        case let (nil, new?):
            return EntryChange(
                relativePath: path,
                change: .added,
                baselineLogical: 0,
                currentLogical: new.logicalSize,
                logicalDelta: new.logicalSize,
                baselineAllocated: nil,
                currentAllocated: new.allocatedSize,
                kind: new.kind,
                countsTowardTotal: new.countsTowardTotal,
                note: new.hardLinkNote
            )
        case (nil, nil):
            return nil
        }
    }
}

public struct ChildRollup: Equatable, Sendable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var baselineLogical: Int64
    public var currentLogical: Int64
    public var logicalDelta: Int64

    public init(relativePath: String, baselineLogical: Int64, currentLogical: Int64, logicalDelta: Int64) {
        self.relativePath = relativePath
        self.baselineLogical = baselineLogical
        self.currentLogical = currentLogical
        self.logicalDelta = logicalDelta
    }

    public static func build(baseline: SpaceSnapshot, current: SpaceSnapshot) -> [ChildRollup] {
        var baselineBytes: [String: Int64] = [:]
        var currentBytes: [String: Int64] = [:]
        for entry in baseline.entriesByPath.values where entry.countsTowardTotal {
            baselineBytes[topChild(entry.relativePath), default: 0] += entry.logicalSize
        }
        for entry in current.entriesByPath.values where entry.countsTowardTotal {
            currentBytes[topChild(entry.relativePath), default: 0] += entry.logicalSize
        }
        let names = Set(baselineBytes.keys).union(currentBytes.keys)
        return names.map { name in
            let before = baselineBytes[name] ?? 0
            let after = currentBytes[name] ?? 0
            return ChildRollup(
                relativePath: name,
                baselineLogical: before,
                currentLogical: after,
                logicalDelta: after - before
            )
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    private static func topChild(_ relativePath: String) -> String {
        if relativePath == "." || relativePath.isEmpty {
            return "."
        }
        if let slash = relativePath.firstIndex(of: "/") {
            return String(relativePath[..<slash])
        }
        return relativePath
    }
}

public enum GrowthSort: String, Sendable, CaseIterable {
    case growthDescending
    case growthAscending
    case currentSizeDescending
    case pathAscending
}

public enum ChangeSorting {
    public static func sort(_ changes: [EntryChange], by order: GrowthSort) -> [EntryChange] {
        changes.sorted { lhs, rhs in
            switch order {
            case .growthDescending:
                if lhs.logicalDelta != rhs.logicalDelta { return lhs.logicalDelta > rhs.logicalDelta }
            case .growthAscending:
                if lhs.logicalDelta != rhs.logicalDelta { return lhs.logicalDelta < rhs.logicalDelta }
            case .currentSizeDescending:
                if lhs.currentLogical != rhs.currentLogical { return lhs.currentLogical > rhs.currentLogical }
            case .pathAscending:
                break
            }
            return lhs.relativePath < rhs.relativePath
        }
    }

    public static func sort(_ rollups: [ChildRollup], by order: GrowthSort) -> [ChildRollup] {
        rollups.sorted { lhs, rhs in
            switch order {
            case .growthDescending:
                if lhs.logicalDelta != rhs.logicalDelta { return lhs.logicalDelta > rhs.logicalDelta }
            case .growthAscending:
                if lhs.logicalDelta != rhs.logicalDelta { return lhs.logicalDelta < rhs.logicalDelta }
            case .currentSizeDescending:
                if lhs.currentLogical != rhs.currentLogical { return lhs.currentLogical > rhs.currentLogical }
            case .pathAscending:
                break
            }
            return lhs.relativePath < rhs.relativePath
        }
    }
}
