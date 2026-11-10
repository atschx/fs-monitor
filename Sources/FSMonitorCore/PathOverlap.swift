import Foundation

public enum PathOverlap {
    public static func overlaps(entryPath: String, eventPath: String) -> Bool {
        if entryPath == "." || eventPath == "." || entryPath.isEmpty || eventPath.isEmpty {
            return entryPath == eventPath
        }
        if entryPath == eventPath {
            return true
        }
        if eventPath.hasPrefix(entryPath + "/") || entryPath.hasPrefix(eventPath + "/") {
            return true
        }
        return false
    }

    /// 统计大小有变化的路径里，有多少条和某条 FSEvents 路径发生组件级重叠。
    /// 根事件 `"."` 不会算成解释了每一个文件。
    public static func growthPathsOverlappingEvidence(diff: SnapshotDiff, evidence: [OperationEvidence]) -> Int {
        let eventPaths = evidence.map(\.relativePath)
        let eventSet = Set(eventPaths)
        let sortedEvents = eventPaths.sorted()
        var count = 0
        for change in diff.changes where change.change != .unchanged {
            if overlaps(entry: change.relativePath, eventSet: eventSet, sortedEvents: sortedEvents) {
                count += 1
            }
        }
        return count
    }

    private static func overlaps(entry: String, eventSet: Set<String>, sortedEvents: [String]) -> Bool {
        if entry == "." {
            return eventSet.contains(".")
        }
        if eventSet.contains(entry) {
            return true
        }
        var ancestor = entry
        while let slash = ancestor.lastIndex(of: "/") {
            ancestor = String(ancestor[..<slash])
            if ancestor.isEmpty || ancestor == "." {
                break
            }
            if eventSet.contains(ancestor) {
                return true
            }
        }
        let prefix = entry + "/"
        var lower = 0
        var upper = sortedEvents.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if sortedEvents[mid] < prefix {
                lower = mid + 1
            } else {
                upper = mid
            }
        }
        return lower < sortedEvents.count && sortedEvents[lower].hasPrefix(prefix)
    }
}
