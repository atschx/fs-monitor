import Foundation
import XCTest
@testable import FSMonitorCore

enum TestDataMark {
    static let banner = "【测试数据】这是 FSMonitor 的隔离演示或测试夹具，不是用户数据。\n"
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fs-monitor-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTempDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func writeMarkedFile(at url: URL, extraBytes: Int) throws -> Int {
    var data = Data(TestDataMark.banner.utf8)
    if extraBytes > 0 {
        data.append(Data(repeating: 0x5A, count: extraBytes))
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
    return data.count
}

func fixedDate(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

func reading(
    pid: Int32,
    name: String,
    read: UInt64? = nil,
    write: UInt64? = nil,
    logical: UInt64? = nil,
    unavailable: String? = nil
) -> ProcessIOReading {
    ProcessIOReading(
        pid: pid,
        name: name,
        wholeProcessBytesRead: read,
        wholeProcessBytesWritten: write,
        wholeProcessLogicalWrites: logical,
        unavailableReason: unavailable
    )
}

func sample(_ readings: [ProcessIOReading], at seconds: TimeInterval, listError: String? = nil) -> ProcessIOSnapshot {
    ProcessIOSnapshot(
        sampledAt: fixedDate(seconds),
        readings: readings,
        probeNote: ProcessIOCorrelation.probeNote,
        listError: listError
    )
}
