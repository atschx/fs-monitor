import Foundation

public enum ProcessIOCorrelation {
    public static let scopeNote = "全进程磁盘读写计数，不是目标目录的 I/O。"
    public static let probeNote = "来源是 proc_pid_rusage(RUSAGE_INFO_V4) 的 ri_diskio_bytesread、ri_diskio_byteswritten 和 ri_logical_writes。它们是该进程启动以来的全进程累计值，不是目标目录的 I/O。调用失败时没有数值。"
    public static let displayLimit = 200

    public static func correlate(
        from start: ProcessIOSnapshot,
        to end: ProcessIOSnapshot,
        displayLimit: Int = ProcessIOCorrelation.displayLimit
    ) -> ProcessCorrelationResult {
        var startByPID: [Int32: ProcessIOReading] = [:]
        for reading in start.readings where reading.pid > 0 {
            startByPID[reading.pid] = reading
        }
        var endPIDs = Set<Int32>()
        var deltas: [ProcessIODelta] = []
        var unchanged = 0
        var unavailable = 0
        var pidReuse = 0
        var appearedOrExited = 0

        for reading in end.readings where reading.pid > 0 {
            endPIDs.insert(reading.pid)
            guard let previous = startByPID[reading.pid] else {
                appearedOrExited += 1
                continue
            }
            if previous.name != reading.name {
                pidReuse += 1
                continue
            }
            let readDelta = positiveDelta(previous.wholeProcessBytesRead, reading.wholeProcessBytesRead)
            let writeDelta = positiveDelta(previous.wholeProcessBytesWritten, reading.wholeProcessBytesWritten)
            let logicalDelta = positiveDelta(previous.wholeProcessLogicalWrites, reading.wholeProcessLogicalWrites)
            let numeric = [readDelta, writeDelta, logicalDelta].compactMap { $0 }
            if numeric.isEmpty {
                unavailable += 1
                continue
            }
            if numeric.allSatisfy({ $0 == 0 }) {
                unchanged += 1
                continue
            }
            deltas.append(ProcessIODelta(
                pid: reading.pid,
                name: reading.name,
                wholeProcessReadDelta: readDelta,
                wholeProcessWriteDelta: writeDelta,
                wholeProcessLogicalWriteDelta: logicalDelta,
                scopeNote: scopeNote
            ))
        }

        for pid in startByPID.keys where !endPIDs.contains(pid) {
            appearedOrExited += 1
        }

        deltas.sort { lhs, rhs in
            let leftWrite = lhs.wholeProcessWriteDelta ?? 0
            let rightWrite = rhs.wholeProcessWriteDelta ?? 0
            if leftWrite != rightWrite { return leftWrite > rightWrite }
            let leftLogical = lhs.wholeProcessLogicalWriteDelta ?? 0
            let rightLogical = rhs.wholeProcessLogicalWriteDelta ?? 0
            if leftLogical != rightLogical { return leftLogical > rightLogical }
            let leftRead = lhs.wholeProcessReadDelta ?? 0
            let rightRead = rhs.wholeProcessReadDelta ?? 0
            if leftRead != rightRead { return leftRead > rightRead }
            return lhs.pid < rhs.pid
        }

        let limit = max(0, displayLimit)
        let truncated = max(0, deltas.count - limit)
        if deltas.count > limit {
            deltas = Array(deltas.prefix(limit))
        }

        return ProcessCorrelationResult(
            deltas: deltas,
            omittedBecauseUnchanged: unchanged,
            omittedBecauseUnavailable: unavailable,
            omittedBecausePIDReuse: pidReuse,
            omittedBecauseNewOrExited: appearedOrExited,
            truncatedCount: truncated
        )
    }

    /// 任一端没有数值，或计数下降（进程重启、回绕）时返回 nil，避免把差值伪装成一个巨大的无符号数。
    private static func positiveDelta(_ start: UInt64?, _ end: UInt64?) -> UInt64? {
        guard let start, let end, end >= start else { return nil }
        return end - start
    }
}
