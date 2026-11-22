#if os(macOS)
import Foundation
import DemoFirstScreenCore

/// Explicit opt-in only: --local-diagnostics-dir <new-isolate>/local-diagnostics.
/// At most 512 numeric/bool records, one writer + one pending snapshot. No event
/// text, window titles, screen coordinates, other apps or global event monitors.
final class LocalDiagnostics {
    static let shared = LocalDiagnostics()
    enum Source: String { case osLocal = "os-local", view = "view-lifecycle", clock, raster, inAppEvidence = "in-app-evidence" }
    private let destination: URL?
    private let writer = DispatchQueue(label: "demo.local-diagnostics.writer", qos: .utility)
    private var rows: [[String: Any]] = []
    private var writing = false
    private var pending = false
    private var lastFlush = 0.0
    private var flushTimer: Timer?
    private let start = ProcessInfo.processInfo.systemUptime
    var enabled: Bool { destination != nil }
    private init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--local-diagnostics-dir"), i+1 < args.count {
            destination = URL(fileURLWithPath: args[i+1], isDirectory: true)
        } else { destination = nil }
    }
    /// Call on main. Values are local coordinates/durations/scales/counters only.
    func record(_ kind: String, source: Source, values: [String: Double] = [:], flags: [String: Bool] = [:]) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var row: [String: Any] = ["kind": kind, "source": source.rawValue, "seconds": now-start]
        for (k,v) in values where v.isFinite { row[k] = v }
        for (k,v) in flags { row[k] = v }
        rows.append(row)
        if rows.count > 512 { rows.removeFirst(rows.count-512) }
        if now-lastFlush >= 2 { lastFlush = now; flush() }
        else if flushTimer == nil {
            let t = Timer(timeInterval: 2-(now-lastFlush), repeats: false) { [weak self] _ in
                guard let self else { return }
                self.flushTimer = nil
                self.lastFlush = ProcessInfo.processInfo.systemUptime
                self.flush()
            }
            flushTimer = t; RunLoop.main.add(t, forMode: .common)
        }
    }
    func flush() {
        guard let destination else { return }
        if writing { pending = true; return }
        writing = true
        let snapshot = rows
        writer.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let payload: [String: Any] = ["note": "Bounded app-local diagnostics. os-local means an NSView event callback, in-app-evidence means synthetic goals. No proof of OS delivery from injected sessions.", "capacity": 512, "records": snapshot]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: destination.appendingPathComponent("local-events-and-render.json"), options: .atomic)
            } catch { fputs("local diagnostics write failed\n", stderr) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.writing = false
                if self.pending { self.pending = false; self.flush() }
            }
        }
    }
}
#endif
