#if os(macOS)
import AppKit
import Combine
import DemoFirstScreenCore

struct EyeImagePair {
    var left: NSImage
    var right: NSImage
    var target: Point2D
    var rasterMilliseconds: Double
}

/// Main-thread clock/publisher; CPU raster is off-main on ONE serial queue.
/// Bounded: one in-flight pair, one latest pending target, one displayed pair.
/// No per-event bitmap work, unbounded cache, global input or background service.
final class EyeFrameDriver: ObservableObject {
    let gpu:IntegratedGPUEyes?
    @Published private(set) var pair: EyeImagePair?
    private(set) var motion: SharedGazeMotion
    private let frozen: Bool
    private let source: LocalDiagnostics.Source
    private let worker = DispatchQueue(label: "demo.eye.raster", qos: .userInitiated)
    private var timer: Timer?
    private var inFlight = false
    private var pending: Point2D?
    private var lastSubmitted: Point2D?
    private var stopped = false
    private(set) var publishedCount: UInt64 = 0
    var diagnosticRenderSource: LocalDiagnostics.Source { source == .inAppEvidence ? .inAppEvidence : .raster }
    var onFirstFrame: (() -> Void)?
    var onPublished: ((EyeImagePair) -> Void)?

    init(target: Point2D, frozen: Bool = false, source: LocalDiagnostics.Source = .clock, gpu:IntegratedGPUEyes? = nil) {
        self.gpu=gpu
        self.frozen = frozen; self.source = source
        motion = SharedGazeMotion(target: target, time: ProcessInfo.processInfo.systemUptime,
                                  reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if frozen {
            // Intentional deterministic offscreen-only path. Never used for live
            // per-pointer drawing. AppKit cacheDisplay itself requires main.
            let begin = ProcessInfo.processInfo.systemUptime
            let l = SphereRasterBuffer.render(spec: .left, pose: SphereGaze.pose(spec: .left, target: target))
            let r = SphereRasterBuffer.render(spec: .right, pose: SphereGaze.pose(spec: .right, target: target))
            if let li = SphereEyeRaster.nsImage(buffer: l), let ri = SphereEyeRaster.nsImage(buffer: r) {
                pair = EyeImagePair(left: li, right: ri, target: target, rasterMilliseconds: (ProcessInfo.processInfo.systemUptime-begin)*1000)
            }
        }
    }
    deinit { timer?.invalidate() }
    func start() { guard !frozen, !stopped else { return }; if let gpu {gpu.onReady={ [weak self] in self?.onFirstFrame?();self?.onFirstFrame=nil};gpu.start();return};submit(motion.position) }
    func stop() { stopped = true; timer?.invalidate(); timer = nil; pending = nil }
    func retarget(_ target: Point2D, reduced: Bool) {
        guard !frozen, !stopped else { return }
        if let gpu {gpu.retarget(target,reduced:reduced);return}
        motion.retarget(target, at: ProcessInfo.processInfo.systemUptime, reduced: reduced)
        LocalDiagnostics.shared.record("goal", source: source,
            values: ["targetX": target.x, "targetY": target.y], flags: ["reduceMotion": reduced])
        if inFlight { pending = motion.position } // discard old queued future pose
        if reduced { timer?.invalidate(); timer = nil; submit(target) }
        else {
            if timer == nil {
                let t = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
                timer = t; RunLoop.main.add(t, forMode: .common)
            }
            // Do not reset clock, velocity or progress on each pointer event.
        }
    }
    private func tick() {
        guard !stopped else { return }
        let oldTime = motion.time
        let p = motion.advance(to: ProcessInfo.processInfo.systemUptime)
        LocalDiagnostics.shared.record("motion-frame", source: source,
            values: ["x": p.x, "y": p.y, "targetX": motion.target.x, "targetY": motion.target.y,
                     "integrationDt": motion.time-oldTime, "integrationStep": Double(motion.frameIndex)], flags: ["settled": motion.settled])
        submit(p)
        if motion.settled { timer?.invalidate(); timer = nil }
    }
    private func submit(_ point: Point2D) {
        if inFlight { pending = point; return }
        if lastSubmitted == point, pair?.target == point { return }
        inFlight = true; lastSubmitted = point
        worker.async { [weak self] in
            let start = ProcessInfo.processInfo.systemUptime
            let left = SphereRasterBuffer.render(spec: .left, pose: SphereGaze.pose(spec: .left, target: point))
            let right = SphereRasterBuffer.render(spec: .right, pose: SphereGaze.pose(spec: .right, target: point))
            let completed = ProcessInfo.processInfo.systemUptime
            let elapsed = (completed-start)*1000
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard !self.stopped else { return }
                // Reduce Motion never publishes an outdated intermediate result.
                let wrapBegan = ProcessInfo.processInfo.systemUptime
                if (!self.motion.reduced || point == self.motion.target),
                   let l = SphereEyeRaster.nsImage(buffer: left), let r = SphereEyeRaster.nsImage(buffer: right) {
                    let first = self.pair == nil
                    let frame = EyeImagePair(left: l, right: r, target: point, rasterMilliseconds: elapsed)
                    self.pair = frame
                    self.publishedCount &+= 1
                    LocalDiagnostics.shared.record("raster-published", source: self.source == .inAppEvidence ? .inAppEvidence : .raster,
                        values: ["x": point.x, "y": point.y, "rasterMs": elapsed, "publicationIndex": Double(self.publishedCount),
                                 "mainQueueWaitMs": (wrapBegan-completed)*1000,
                                 "imageWrapMs": (ProcessInfo.processInfo.systemUptime-wrapBegan)*1000,
                                 "leftPixelsW": Double(left.width), "leftPixelsH": Double(left.height),
                                 "rightPixelsW": Double(right.width), "rightPixelsH": Double(right.height)])
                    if first { self.onFirstFrame?(); self.onFirstFrame = nil }
                    self.onPublished?(frame)
                }
                if let latest = self.pending { self.pending = nil; self.submit(latest) }
            }
        }
    }
}
#endif
