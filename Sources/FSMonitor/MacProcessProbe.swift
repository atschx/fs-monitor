#if os(macOS)
import Foundation
import FSMonitorCore
import FSMonitorProc

struct MacProcessProbe: Sendable {
    func sample(now: Date = Date()) -> ProcessIOSnapshot {
        let count = fsmonitor_pid_count()
        guard count > 0 else {
            return ProcessIOSnapshot(
                sampledAt: now,
                readings: [],
                probeNote: ProcessIOCorrelation.probeNote,
                listError: "proc_listallpids 失败。没有可展示的全进程计数。"
            )
        }
        let capacity = Int(count) + 128
        var pids = [Int32](repeating: 0, count: capacity)
        let got = pids.withUnsafeMutableBufferPointer { buffer in
            fsmonitor_copy_pids(buffer.baseAddress, Int32(buffer.count))
        }
        guard got > 0 else {
            return ProcessIOSnapshot(
                sampledAt: now,
                readings: [],
                probeNote: ProcessIOCorrelation.probeNote,
                listError: "proc_listallpids 没有返回进程。没有可展示的全进程计数。"
            )
        }

        var readings: [ProcessIOReading] = []
        var seen = Set<Int32>()
        readings.reserveCapacity(Int(got))
        for pid in pids.prefix(Int(got)) where pid > 0 && seen.insert(pid).inserted {
            readings.append(read(pid: pid))
        }
        return ProcessIOSnapshot(
            sampledAt: now,
            readings: readings,
            probeNote: ProcessIOCorrelation.probeNote,
            listError: nil
        )
    }

    private func read(pid: Int32) -> ProcessIOReading {
        let name = processName(pid: pid)
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var logicalWrites: UInt64 = 0
        var errorNumber: Int32 = 0
        let rc = fsmonitor_proc_rusage(pid, &bytesRead, &bytesWritten, &logicalWrites, &errorNumber)
        guard rc == 0 else {
            return ProcessIOReading(
                pid: pid,
                name: name,
                wholeProcessBytesRead: nil,
                wholeProcessBytesWritten: nil,
                wholeProcessLogicalWrites: nil,
                unavailableReason: "proc_pid_rusage 失败（errno \(errorNumber)）。"
            )
        }
        return ProcessIOReading(
            pid: pid,
            name: name,
            wholeProcessBytesRead: bytesRead,
            wholeProcessBytesWritten: bytesWritten,
            wholeProcessLogicalWrites: logicalWrites,
            unavailableReason: nil
        )
    }

    private func processName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let rc = buffer.withUnsafeMutableBufferPointer { pointer in
            fsmonitor_process_name(pid, pointer.baseAddress, Int32(pointer.count))
        }
        guard rc > 0 else { return "未知进程" }
        let text = String(cString: buffer)
        let name = URL(fileURLWithPath: text).lastPathComponent
        return name.isEmpty ? "未知进程" : name
    }
}
#endif
