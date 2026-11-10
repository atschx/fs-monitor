#if os(macOS)
import CoreServices
import Foundation

struct RawFSEvent {
    var observedAt: Date
    var absolutePath: String
    var rawFlags: UInt32
    var eventID: UInt64
    var generation: Int
}

final class MacFSEventsMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var handler: ((RawFSEvent) -> Void)?
    private var generation = 0
    private let queue = DispatchQueue(label: "fs-monitor.fsevents")

    func setGeneration(_ value: Int) {
        lock.lock()
        generation = value
        lock.unlock()
    }

    func start(path: String, handler: @escaping (RawFSEvent) -> Void) throws {
        stop()
        lock.lock()
        self.handler = handler
        lock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            nil,
            MacFSEventsMonitor.callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            lock.lock()
            self.handler = nil
            lock.unlock()
            throw MonitorFailure(message: "无法创建 FSEvents 流。这不需要 root，但所选目录必须可读。")
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            lock.lock()
            self.handler = nil
            lock.unlock()
            throw MonitorFailure(message: "无法启动 FSEvents 流。没有开始监控。")
        }
        lock.lock()
        stream = created
        lock.unlock()
    }

    func stop() {
        lock.lock()
        handler = nil
        let current = stream
        stream = nil
        lock.unlock()
        guard let current else { return }
        FSEventStreamStop(current)
        FSEventStreamInvalidate(current)
        FSEventStreamRelease(current)
    }

    fileprivate func emit(path: String, flags: FSEventStreamEventFlags, eventID: FSEventStreamEventId) {
        lock.lock()
        let currentHandler = handler
        let currentGeneration = generation
        lock.unlock()
        currentHandler?(RawFSEvent(
            observedAt: Date(),
            absolutePath: path,
            rawFlags: UInt32(flags),
            eventID: UInt64(eventID),
            generation: currentGeneration
        ))
    }

    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, eventIds in
        guard let info, numEvents > 0 else { return }
        let monitor = Unmanaged<MacFSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
        let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        let count = min(numEvents, CFArrayGetCount(array))
        for index in 0..<count {
            guard let rawPointer = CFArrayGetValueAtIndex(array, index) else { continue }
            let path = Unmanaged<CFString>.fromOpaque(rawPointer).takeUnretainedValue() as String
            monitor.emit(path: path, flags: eventFlags[index], eventID: eventIds[index])
        }
    }

    deinit {
        stop()
    }
}

struct MonitorFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
#endif
