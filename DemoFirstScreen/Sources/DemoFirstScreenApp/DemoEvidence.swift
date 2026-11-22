#if os(macOS)
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import DemoFirstScreenCore

/// In-app offscreen rendering and window-attribute logs.
/// This is not a capture of the user's screen and is not GUI automation.
/// Input is delivered only through InteractionSession.pointerMoved, the same
/// path the live NSView.mouseMoved handler uses.
enum DemoEvidence {
    static let logicalWidth: CGFloat = 1200
    static let logicalHeight: CGFloat = 900
    static let evidenceCaption = "应用内输入/渲染验证，非真人鼠标操作屏幕录像"

    static func writeWindowProperties(_ window: NSWindow, to directory: URL) throws {
        let close = window.standardWindowButton(.closeButton)
        let mini = window.standardWindowButton(.miniaturizeButton)
        let zoom = window.standardWindowButton(.zoomButton)
        let mask = window.styleMask
        let bg = window.backgroundColor
        let scale = window.backingScaleFactor
        let payload: [String: Any] = [
            "note": "Window attributes recorded from the NSWindow object. Not a user-screen screenshot.",
            "recordedAt": isoNow(),
            "styleMaskRaw": mask.rawValue,
            "styleMask": [
                "borderless": mask.contains(.borderless),
                "titled": mask.contains(.titled),
                "closable": mask.contains(.closable),
                "miniaturizable": mask.contains(.miniaturizable),
                "resizable": mask.contains(.resizable),
                "fullSizeContentView": mask.contains(.fullSizeContentView)
            ],
            "titleVisibilityHidden": window.titleVisibility == .hidden,
            "titlebarAppearsTransparent": window.titlebarAppearsTransparent,
            "isOpaque": window.isOpaque,
            "hasShadow": window.hasShadow,
            "backgroundColorAlpha": bg?.alphaComponent ?? -1,
            "backgroundIsClear": (bg?.alphaComponent ?? 1) == 0,
            "backingScaleFactor": scale,
            "isMovableByWindowBackground": window.isMovableByWindowBackground,
            "acceptsMouseMovedEvents": window.acceptsMouseMovedEvents,
            "frame": [window.frame.origin.x, window.frame.origin.y, window.frame.width, window.frame.height],
            "trafficLights": [
                "closeExists": close != nil,
                "closeHidden": close?.isHidden ?? true,
                "miniaturizeExists": mini != nil,
                "miniaturizeHidden": mini?.isHidden ?? true,
                "zoomExists": zoom != nil,
                "zoomHidden": zoom?.isHidden ?? true
            ],
            "trulyChromeLess": !mask.contains(.titled)
                && close == nil && mini == nil && zoom == nil,
            "transparentWindow": window.isOpaque == false && (bg?.alphaComponent ?? 1) == 0
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("window-properties.json"))
        let readme = """
        # 窗口属性与离屏渲染证据

        这些文件由 Demo 进程在 App 内写出，不是用户屏幕截图，也不是 GUI 自动化。
        离屏图用自建 `NSBitmapImageRep`（按实际 backingScaleFactor 的像素尺寸）
        对 `ClearHostingView` 做 `cacheDisplay`，不调用截屏 API，不注入全局鼠标。

        输入只走 `InteractionSession.pointerMoved`，与 `NSView.mouseMoved` 同一局部处理路径。

        标注原文：\(evidenceCaption)

        `window-properties.json` 记录 styleMask、isOpaque、background alpha、三按钮、backingScaleFactor。
        `alpha-samples-coral-board-and-eye-bounds.json` 记录叠唇/盘后板 alpha（期望 255）
        与 lipMinY 以上去顶铺底采样（期望 0），以及眼轮廓是否完整落在画幅内。
        眼层：壳体椭圆固定，眼球为C1隐式光滑并集巩膜球+角膜穹顶；光线折射至内嵌虹膜面，有限面光源由真实角膜法线反射；眼睑为固定椭球壳/柔和卷边，不再叠大块AO椭圆。金属轴心仍为 D2-1024 位图裁切。程序材质参照 D2 色板，不是 218×127 眼裁切的锐化或生成放大。
        `gaze-png-assertions.json` 在 cacheDisplay 的最终 PNG 上测虹膜质心（相对巩膜球心，画布 +Y 向下），不单信 pose JSON 向量。
        """
        try readme.write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }

    static func writeOffscreenFrames(example: DemoSnapshot, to directory: URL) throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        var overview = InteractionSession(snapshot: example)
        let overviewRep = try render(session: overview, scale: scale)
        try writeAnnotated(
            overviewRep,
            name: "offscreen-overview-NOT-a-user-screenshot",
            scale: scale,
            caption: "总览 · 默认注视最大区 Movies · 五区核心文字 · 静态不能证明转动",
            extra: nil,
            to: directory
        )
        try writeCheckerComposite(overviewRep, name: "offscreen-overview-on-checker-NOT-a-user-screenshot.png", scale: scale, to: directory)
        try writeEyeBoundsReport(to: directory)
        try writeAlphaReport(overviewRep, scale: scale, to: directory)

        let hoverPoint = overview.layout.pointOnRay(degrees: 200, radiusFraction: 0.55)
        overview.pointerMoved(to: hoverPoint)
        let hoverRep = try render(session: overview, scale: scale)
        let hoverEye = FramePresentation.make(session: overview, motion: .reduced, pointerInsideWindow: true).eye
        try writeAnnotated(
            hoverRep,
            name: "offscreen-hover-movies-NOT-a-user-screenshot",
            scale: scale,
            caption: "hover 影片",
            extra: overlayText(point: hoverPoint, eye: hoverEye, sector: "Movies"),
            to: directory
        )

        overview.pointerClicked(at: hoverPoint)
        let lockedRep = try render(session: overview, scale: scale)
        try writeAnnotated(
            lockedRep,
            name: "offscreen-locked-movies-NOT-a-user-screenshot",
            scale: scale,
            caption: "锁定 影片",
            extra: overlayText(point: hoverPoint, eye: hoverEye, sector: "Movies"),
            to: directory
        )

        try writeGazeSequence(example: example, scale: scale, to: directory)
        try writeWindowBoundarySequence(example: example, scale: scale, to: directory)
        try writeSeamInterpolationSequence(example: example, scale: scale, to: directory)
        var wide = InteractionSession(snapshot: example)
        let map = WindowCanvasMap(width: 1600, height: 900)
        wide.pointerMoved(to: map.canvasPoint(Point2D(x: 20, y: 450)))
        let wideRep = try render(session: wide, scale: scale, logicalSize: NSSize(width: 1600, height: 900))
        if let data = wideRep.representation(using: .png, properties: [:]) {
            try data.write(to: directory.appendingPathComponent("wide-window-letterbox-injected-NOT-a-user-screenshot.png"))
        }
    }

    static func writeMinimalPerformanceEvidence(example: DemoSnapshot, to directory: URL) throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var session = InteractionSession(snapshot: example)
        let pictures = session.layout.pointOnRay(degrees: 312, radiusFraction: 0.55)
        let projects = session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        let cases: [(String, Point2D?)] = [("default", nil), ("projects", projects),
            ("join-midpoint", Point2D(x: (pictures.x+projects.x)*0.5, y: (pictures.y+projects.y)*0.5))]
        for (name, point) in cases {
            if let point { session.pointerMoved(to: point) }
            let rep = try render(session: session, scale: scale)
            if let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: directory.appendingPathComponent("minimal-"+name+"-NOT-a-user-screenshot.png"))
            }
        }
        let note = "Three App cacheDisplay frames only. Performance-only cache change; not OS input or GUI smoothness acceptance."
        try Data(note.utf8).write(to: directory.appendingPathComponent("minimal-evidence-note.txt"))
    }

    private static var clockEvidenceDriver: EyeFrameDriver?

    /// Runs the actual Timer -> shared motion -> off-main raster -> pair publisher
    /// chain with synthetic goals. Each full cacheDisplay uses the PUBLISHED pair,
    /// not a pose JSON re-created afterward. Still not OS input or GUI FPS proof.
    static func writeClockDrivenGazeEvidence(example: DemoSnapshot, to directory: URL) {
        let session = InteractionSession(snapshot: example)
        let rest = SphereGaze.defaultTarget(sectors: session.chartability.sectors, layout: session.layout)
        let driver = EyeFrameDriver(target: rest, source: .inAppEvidence)
        clockEvidenceDriver = driver
        let folder = directory.appendingPathComponent("clock-pipeline-sequence", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return }
        var phase = 0, phaseFrames = 0, index = 0
        var records: [[String: Any]] = []
        let began = ProcessInfo.processInfo.systemUptime
        driver.onPublished = { [weak driver] pair in
            guard let driver else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime-began
            let labels = ["initial", "window-blank-follow", "window-exit-return", "reenter-transparent"]
            let isEnd = driver.motion.settled && pair.target == driver.motion.target
            // Bounded artifact capture, independent of motion-frame log capacity.
            if phaseFrames < 5 || isEnd {
                do {
                    let rep = try render(session: session, scale: NSScreen.main?.backingScaleFactor ?? 2, eyeFrames: driver)
                    let name = String(format: "clock-%02d-%@-NOT-a-user-screenshot.png", index, labels[phase])
                    if let raw = rep.representation(using: .png, properties: [:]) { try raw.write(to: folder.appendingPathComponent(name)) }
                    var record: [String: Any] = ["index": index, "phase": labels[phase], "file": name,
                        "seconds": elapsed, "publishedTarget": [pair.target.x, pair.target.y],
                        "goal": [driver.motion.target.x, driver.motion.target.y],
                        "integrationStep": driver.motion.frameIndex, "publicationIndex": driver.publishedCount, "settled": isEnd,
                        "rasterMilliseconds": pair.rasterMilliseconds]
                    var measured = session
                    measured.pointerMoved(to: pair.target)
                    let publishedPose = FramePresentation.make(session: measured, motion: .reduced, pointerInsideWindow: true)
                    pngGazeFields(rep, frame: publishedPose, scale: NSScreen.main?.backingScaleFactor ?? 2).forEach { record[$0] = $1 }
                    records.append(record)
                    index += 1
                } catch { fputs("clock evidence frame failed\n", stderr) }
            }
            phaseFrames += 1
            if isEnd {
                if phase == 0 { phase = 1; phaseFrames = 0; driver.retarget(Point2D(x: 2180, y: 200), reduced: false) }
                else if phase == 1 { phase = 2; phaseFrames = 0; driver.retarget(rest, reduced: false) }
                else if phase == 2 { phase = 3; phaseFrames = 0; driver.retarget(Point2D(x: 80, y: 80), reduced: false) }
                else {
                    driver.stop()
                    let report: [String: Any] = ["note": "Actual app Timer/async-raster publication samples, synthetic goals, not OS pointer dispatch or real GUI frame-rate acceptance. cacheDisplay capture itself adds main-thread overhead.",
                        "complete": true, "osInputVerified": false, "transparentOSDeliveryVerified": false, "liveGUIFPSVerified": false,
                        "frames": records]
                    do {
                        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                        try data.write(to: directory.appendingPathComponent("clock-pipeline-sequence.json"))
                    } catch { fputs("clock evidence report failed\n", stderr) }
                    LocalDiagnostics.shared.flush()
                    driver.onPublished = nil
                    clockEvidenceDriver = nil
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak driver] in
            guard let driver, clockEvidenceDriver === driver else { return }
            driver.stop(); driver.onPublished = nil; clockEvidenceDriver = nil
            let failed: [String: Any] = ["complete": false, "reason": "90s bounded in-app evidence timeout, not an OS-input failure", "frames": records]
            if let data = try? JSONSerialization.data(withJSONObject: failed, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("clock-pipeline-sequence.json"))
            }
            LocalDiagnostics.shared.flush()
        }
        driver.start()
    }

    /// Samples the SAME shared canvas-target segment used by eye interpolation,
    /// concentrated around Pictures -> Projects where 080440's glint was cut.
    /// These are pose samples, not a wall-clock GUI animation recording.
    private static func writeSeamInterpolationSequence(example: DemoSnapshot, scale: CGFloat, to directory: URL) throws {
        var session = InteractionSession(snapshot: example)
        let a = session.layout.pointOnRay(degrees: 328, radiusFraction: 0.55)
        let b = session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        let dir = directory.appendingPathComponent("seam-interpolation-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        for index in 0...8 {
            let t = Double(index) / 8
            let target = Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            session.pointerMoved(to: target)
            let frame = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: true)
            let rep = try render(session: session, scale: scale)
            let name = String(format: "seam-%02d-NOT-a-user-screenshot.png", index)
            guard let raw = rep.representation(using: .png, properties: [:]) else { throw EvidenceError.bitmapFailed(name) }
            try raw.write(to: dir.appendingPathComponent(name))
            var record: [String: Any] = ["index": index, "fraction": t, "file": name,
                "sampledSharedTarget": [target.x, target.y],
                "resolvedTarget": [frame.eye.resolvedTarget.x, frame.eye.resolvedTarget.y],
                "followsPointer": frame.eye.followsPointer,
                "leftDirection": [frame.eye.leftPose.direction.x, frame.eye.leftPose.direction.y, frame.eye.leftPose.direction.z],
                "rightDirection": [frame.eye.rightPose.direction.x, frame.eye.rightPose.direction.y, frame.eye.rightPose.direction.z]]
            pngGazeFields(rep, frame: frame, scale: scale).forEach { record[$0] = $1 }
            records.append(record)
        }
        let meta: [String: Any] = ["note": "App cacheDisplay full PNG pose samples of shared-target interpolation Pictures->Projects. Not a user screenshot or real-time GUI smoothness validation.",
            "lightUnchangedFrom080440": true, "irisRadiusUnchanged": true, "shellsUnchanged": true,
            "geometry": "C1 polynomial smooth union, continuous ray-hit normals; reflection independent of iris visibility",
            "frames": records]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("seam-interpolation-sequence.json"))
    }

    /// Five in-app input cases (same local pointerMoved / pointerExited path,
    /// no global event tap): on-disc, off-disc in-window, transparent region,
    /// outside window, re-entry. Lock is kept; all in-window regions keep gaze; only exit returns default.
    private static func writeWindowBoundarySequence(example: DemoSnapshot, scale: CGFloat, to directory: URL) throws {
        var session = InteractionSession(snapshot: example)
        let layout = session.layout
        let onA = layout.pointOnRay(degrees: 190, radiusFraction: 0.50)
        let onB = layout.pointOnRay(degrees: 220, radiusFraction: 0.58)
        let offDisc = Point2D(x: 120, y: 400)
        let transparent = Point2D(x: 80, y: 80)
        let reenter = layout.pointOnRay(degrees: 328, radiusFraction: 0.55)
        let dir = directory.appendingPathComponent("window-boundary-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var records: [[String: Any]] = []
        func record(_ name: String, _ caption: String, insideWindow: Bool) throws {
            let frame = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: insideWindow)
            let rep = try render(session: session, scale: scale)
            try writeAnnotated(
                rep,
                name: "boundary-\(name)-NOT-a-user-screenshot",
                scale: scale,
                caption: caption,
                extra: overlayText(
                    point: session.state.pointerLocation ?? Point2D(x: -1, y: -1),
                    eye: frame.eye,
                    sector: frame.highlightID ?? (session.state.lockedID.map { "L:\($0)" } ?? "")
                ),
                to: dir
            )
            records.append([
                "name": name,
                "pointerCanvas": session.state.pointerLocation.map { [$0.x, $0.y] } as Any,
                "insideWindow": insideWindow,
                "onDisc": session.state.pointerLocation.map { session.hits.isOnDisc($0) } as Any,
                "lockedID": session.state.lockedID as Any,
                "highlightID": frame.highlightID as Any,
                "compactCardIDs": frame.visibleSectorCoreLabels.map(\.id),
                "expandedCardID": frame.infoPlacement.identityID as Any,
                "followsPointer": frame.eye.followsPointer,
                "resolvedTarget": [frame.eye.resolvedTarget.x, frame.eye.resolvedTarget.y],
                "defaultTarget": [frame.eye.defaultTarget.x, frame.eye.defaultTarget.y],
                "defaultTargetID": frame.eye.defaultTargetID as Any,
                "leftPupilOffset": [frame.eye.leftPupilOffset.x, frame.eye.leftPupilOffset.y],
                "rightPupilOffset": [frame.eye.rightPupilOffset.x, frame.eye.rightPupilOffset.y],
                "leftFacing": frame.eye.leftPose.facing,
                "rightFacing": frame.eye.rightPose.facing,
                "leftDirection": [frame.eye.leftPose.direction.x, frame.eye.leftPose.direction.y, frame.eye.leftPose.direction.z],
                "rightDirection": [frame.eye.rightPose.direction.x, frame.eye.rightPose.direction.y, frame.eye.rightPose.direction.z],
                "leftIrisCenter": [frame.eye.leftPose.projectedIrisCenter.x, frame.eye.leftPose.projectedIrisCenter.y],
                "rightIrisCenter": [frame.eye.rightPose.projectedIrisCenter.x, frame.eye.rightPose.projectedIrisCenter.y],
                "leftShellCenter": [frame.eye.leftShellCenter.x, frame.eye.leftShellCenter.y],
                "rightShellCenter": [frame.eye.rightShellCenter.x, frame.eye.rightShellCenter.y]
            ])
        }

        session.pointerClicked(at: onA)
        try record("1-disc-a", "盘内连续 A · 锁定影片", insideWindow: true)
        session.pointerMoved(to: onB)
        try record("2-disc-b", "盘内连续 B", insideWindow: true)
        session.pointerMoved(to: offDisc)
        try record("3-off-disc-in-window", "盘外但窗内 · 连续跟随 · L 信息保留", insideWindow: true)
        session.pointerMoved(to: transparent)
        try record("4-transparent", "透明区 · 继续跟随 · L 信息保留", insideWindow: true)
        session.pointerExitedVisibleArea()
        try record("5-outside-window", "窗口外 · 默认注视 · L 保留", insideWindow: false)
        session.pointerMoved(to: reenter)
        try record("6-reenter-disc", "重入盘 · 恢复跟随 · L 仍在", insideWindow: true)

        let meta: [String: Any] = [
            "note": evidenceCaption,
            "logicalPoints": [logicalWidth, logicalHeight],
            "backingScaleFactor": scale,
            "pixelSize": [logicalWidth * scale, logicalHeight * scale],
            "cases": ["on-disc continuous", "off-disc in-window", "transparent", "outside window", "re-enter"],
            "frames": records
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("window-boundary-sequence.json"))
    }


    /// Iris centroid on the final cacheDisplay bitmap, in canvas pixels (y-down).
    /// Measured against the *sclera* (globe) center, not the lid shell.
    private static func pngIris(
        _ rep: NSBitmapImageRep,
        spec: VectorEyeSpec,
        scale: CGFloat
    ) -> SphereImageMeasure.Result? {
        SphereImageMeasure.darkIrisCentroid(sclera: spec.sclera) { canvasX, canvasY in
            let viewX = Double(canvasX) / 2
            let viewY = Double(canvasY) / 2
            let px = Int((viewX * Double(scale)).rounded())
            let py = Int((viewY * Double(scale)).rounded())
            let cx = min(max(px, 0), Int(logicalWidth * scale) - 1)
            let cy = min(max(py, 0), Int(logicalHeight * scale) - 1)
            guard let color = rep.colorAt(x: cx, y: cy) else { return nil }
            return (
                Int(((color.redComponent) * 255).rounded()),
                Int(((color.greenComponent) * 255).rounded()),
                Int(((color.blueComponent) * 255).rounded()),
                Int(((color.alphaComponent) * 255).rounded())
            )
        }
    }

    private static func pngGazeFields(
        _ rep: NSBitmapImageRep,
        frame: FramePresentation,
        scale: CGFloat
    ) -> [String: Any] {
        let left = pngIris(rep, spec: .left, scale: scale)
        let right = pngIris(rep, spec: .right, scale: scale)
        let target = frame.eye.resolvedTarget
        func side(_ result: SphereImageMeasure.Result?, spec: VectorEyeSpec) -> [String: Any] {
            let dx = target.x - spec.sclera.center.x
            let dy = target.y - spec.sclera.center.y
            var d: [String: Any] = [
                "scleraCenter": [spec.sclera.center.x, spec.sclera.center.y],
                "shellCenter": [spec.shell.center.x, spec.shell.center.y],
                "targetMinusSclera": [dx, dy]
            ]
            if let r = result {
                d["pngIris"] = [r.canvasX, r.canvasY]
                d["pngIrisUnit"] = [r.unitX, r.unitY]
                d["pngSamples"] = r.samples
                d["irisYMatchesTarget"] = SphereImageMeasure.sameDirection(r.unitY, dy)
                d["irisXMatchesTarget"] = SphereImageMeasure.sameDirection(r.unitX, dx)
            } else {
                d["pngIris"] = NSNull()
                d["irisYMatchesTarget"] = false
                d["irisXMatchesTarget"] = false
            }
            return d
        }
        return [
            "pngLeft": side(left, spec: .left),
            "pngRight": side(right, spec: .right),
            "shellCenters": [
                "left": [frame.eye.leftShellCenter.x, frame.eye.leftShellCenter.y],
                "right": [frame.eye.rightShellCenter.x, frame.eye.rightShellCenter.y]
            ]
        ]
    }

    private static func writeGazeSequence(example: DemoSnapshot, scale: CGFloat, to directory: URL) throws {

        var session = InteractionSession(snapshot: example)
        let layout = session.layout
        // Same-sector (Movies 180…234) multiple positions, then cross-sector.
        let steps: [(String, Double, Double)] = [
            ("movies-a", 190, 0.50),
            ("movies-b", 205, 0.58),
            ("movies-c", 220, 0.50),
            ("archives", 252, 0.55),
            ("documents", 297, 0.55),
            ("pictures", 328, 0.55),
            ("projects", 351, 0.55)
        ]
        var records: [[String: Any]] = []
        var images: [NSBitmapImageRep] = []
        let seqDir = directory.appendingPathComponent("gaze-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)

        // Static default (no pointer): looks at Movies. This frame alone is not rotation proof.
        do {
            let idle = InteractionSession(snapshot: example)
            let frame = FramePresentation.make(session: idle, motion: .reduced, pointerInsideWindow: true)
            let rep = try render(session: idle, scale: scale)
            images.append(rep)
            try writeAnnotated(
                rep,
                name: "gaze-default-movies-NOT-a-user-screenshot",
                scale: scale,
                caption: "默认注视最大区 Movies · 静态参考，不能单独证明转动",
                extra: "follows=false  default=Movies",
                to: seqDir
            )
            var defaultRec: [String: Any] = [
                "name": "default-movies",
                "pointerCanvas": NSNull(),
                "highlightID": frame.highlightID as Any,
                "compactCardIDs": frame.visibleSectorCoreLabels.map(\.id),
                "expandedCardID": frame.infoPlacement.identityID as Any,
                "followsPointer": frame.eye.followsPointer,
                "resolvedTarget": [frame.eye.resolvedTarget.x, frame.eye.resolvedTarget.y],
                "defaultTargetID": frame.eye.defaultTargetID as Any,
                "leftDirection": [frame.eye.leftPose.direction.x, frame.eye.leftPose.direction.y, frame.eye.leftPose.direction.z],
                "rightDirection": [frame.eye.rightPose.direction.x, frame.eye.rightPose.direction.y, frame.eye.rightPose.direction.z],
                "leftFacing": frame.eye.leftPose.facing,
                "rightFacing": frame.eye.rightPose.facing,
                "leftIrisCenter": [frame.eye.leftPose.projectedIrisCenter.x, frame.eye.leftPose.projectedIrisCenter.y],
                "rightIrisCenter": [frame.eye.rightPose.projectedIrisCenter.x, frame.eye.rightPose.projectedIrisCenter.y],
                "leftShellCenter": [frame.eye.leftShellCenter.x, frame.eye.leftShellCenter.y],
                "rightShellCenter": [frame.eye.rightShellCenter.x, frame.eye.rightShellCenter.y]
            ]
            pngGazeFields(rep, frame: frame, scale: scale).forEach { defaultRec[$0] = $1 }
            records.append(defaultRec)
        }

        for (name, degrees, frac) in steps {
            let point = layout.pointOnRay(degrees: degrees, radiusFraction: frac)
            session.pointerMoved(to: point)
            let frame = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: true)
            let rep = try render(session: session, scale: scale)
            images.append(rep)
            let labeledName = "gaze-\(name)-NOT-a-user-screenshot"
            try writeAnnotated(
                rep,
                name: labeledName,
                scale: scale,
                caption: "球面转动证据 · \(name) · 非静态总览、非真人截屏",
                extra: overlayText(point: point, eye: frame.eye, sector: frame.highlightID ?? ""),
                to: seqDir
            )
            var rec: [String: Any] = [
                "name": name,
                "pointerCanvas": [point.x, point.y],
                "highlightID": frame.highlightID as Any,
                "compactCardIDs": frame.visibleSectorCoreLabels.map(\.id),
                "expandedCardID": frame.infoPlacement.identityID as Any,
                "followsPointer": frame.eye.followsPointer,
                "resolvedTarget": [frame.eye.resolvedTarget.x, frame.eye.resolvedTarget.y],
                "defaultTarget": [frame.eye.defaultTarget.x, frame.eye.defaultTarget.y],
                "defaultTargetID": frame.eye.defaultTargetID as Any,
                "leftPupilOffset": [frame.eye.leftPupilOffset.x, frame.eye.leftPupilOffset.y],
                "rightPupilOffset": [frame.eye.rightPupilOffset.x, frame.eye.rightPupilOffset.y],
                "leftFacing": frame.eye.leftPose.facing,
                "rightFacing": frame.eye.rightPose.facing,
                "leftDirection": [frame.eye.leftPose.direction.x, frame.eye.leftPose.direction.y, frame.eye.leftPose.direction.z],
                "rightDirection": [frame.eye.rightPose.direction.x, frame.eye.rightPose.direction.y, frame.eye.rightPose.direction.z],
                "leftIrisCenter": [frame.eye.leftPose.projectedIrisCenter.x, frame.eye.leftPose.projectedIrisCenter.y],
                "rightIrisCenter": [frame.eye.rightPose.projectedIrisCenter.x, frame.eye.rightPose.projectedIrisCenter.y],
                "leftShellCenter": [frame.eye.leftShellCenter.x, frame.eye.leftShellCenter.y],
                "rightShellCenter": [frame.eye.rightShellCenter.x, frame.eye.rightShellCenter.y],
                "infoAnchor": [frame.infoPlacement.center.x, frame.infoPlacement.center.y],
                "infoVisible": frame.infoPlacement.isVisible
            ]
            pngGazeFields(rep, frame: frame, scale: scale).forEach { rec[$0] = $1 }
            records.append(rec)
        }

        session.pointerExitedVisibleArea()
        do {
            let frame = FramePresentation.make(session: session, motion: .reduced, pointerInsideWindow: false)
            let rep = try render(session: session, scale: scale)
            images.append(rep)
            try writeAnnotated(
                rep,
                name: "gaze-window-exit-returns-default-NOT-a-user-screenshot",
                scale: scale,
                caption: "实际离窗目标回 Movies · 本帧是settled采样，非动画时序证明",
                extra: "follows=false  default=Movies",
                to: seqDir
            )
            var offRec: [String: Any] = [
                "name": "window-exit-returns-default",
                "pointerCanvas": NSNull(),
                "highlightID": frame.highlightID as Any,
                "compactCardIDs": frame.visibleSectorCoreLabels.map(\.id),
                "expandedCardID": frame.infoPlacement.identityID as Any,
                "followsPointer": frame.eye.followsPointer,
                "resolvedTarget": [frame.eye.resolvedTarget.x, frame.eye.resolvedTarget.y],
                "defaultTargetID": frame.eye.defaultTargetID as Any,
                "leftDirection": [frame.eye.leftPose.direction.x, frame.eye.leftPose.direction.y, frame.eye.leftPose.direction.z],
                "rightDirection": [frame.eye.rightPose.direction.x, frame.eye.rightPose.direction.y, frame.eye.rightPose.direction.z],
                "leftIrisCenter": [frame.eye.leftPose.projectedIrisCenter.x, frame.eye.leftPose.projectedIrisCenter.y],
                "rightIrisCenter": [frame.eye.rightPose.projectedIrisCenter.x, frame.eye.rightPose.projectedIrisCenter.y],
                "leftShellCenter": [frame.eye.leftShellCenter.x, frame.eye.leftShellCenter.y],
                "rightShellCenter": [frame.eye.rightShellCenter.x, frame.eye.rightShellCenter.y]
            ]
            pngGazeFields(rep, frame: frame, scale: scale).forEach { offRec[$0] = $1 }
            records.append(offRec)
        }

        let meta: [String: Any] = [
            "note": evidenceCaption + "  ·  球面转动序列（同区连续 / 跨区）。单张静态总览不能证明转动。默认注视为当前最大示例分区 Movies；仅离窗回该默认。不是自动锁定 L。",
            "logicalPoints": [logicalWidth, logicalHeight],
            "backingScaleFactor": scale,
            "pixelSize": [logicalWidth * scale, logicalHeight * scale],
            "sameSectorSteps": ["movies-a", "movies-b", "movies-c"],
            "crossSectorSteps": ["archives", "documents", "pictures", "projects"],
            "material": "procedural C1 smooth-union corneal dome, refracted recessed iris, finite light reflection, rolled ellipsoidal lid; D2 palette reference, not D2 pixel reproduction; not a planar disc, not a sharpened or AI upscale of d2-eyes-*.png",
            "frames": records
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("gaze-sequence.json"))
        try writeGazePNGAssertions(records: records, to: directory)

        try writeContactSheet(images: images, records: records, scale: scale, to: directory.appendingPathComponent("gaze-sequence-contact-sheet-NOT-a-user-screenshot.png"))
        try writeGIF(images: images, scale: scale, to: directory.appendingPathComponent("gaze-sequence-NOT-a-user-screenshot.gif"))
    }


    private static func writeGazePNGAssertions(records: [[String: Any]], to directory: URL) throws {
        func nest(_ rec: [String: Any], side: String) -> [String: Any] {
            (rec[side] as? [String: Any]) ?? [:]
        }
        func num(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let n = v as? NSNumber { return n.doubleValue }
            if let a = v as? [Any], a.count == 2, let x = num(a[1]) { return x } // unused
            return nil
        }
        func pair(_ v: Any?) -> [Double]? {
            guard let a = v as? [Any], a.count == 2,
                  let x = (a[0] as? NSNumber)?.doubleValue ?? (a[0] as? Double),
                  let y = (a[1] as? NSNumber)?.doubleValue ?? (a[1] as? Double) else { return nil }
            return [x, y]
        }

        var frameNotes: [[String: Any]] = []
        var yMatch = true
        var xMatch = true
        var measured = true
        var defaultIris: ([Double], [Double])?
        var offIris: ([Double], [Double])?
        var shells: [[Double]] = []

        for rec in records {
            let name = rec["name"] as? String ?? "?"
            let left = nest(rec, side: "pngLeft")
            let right = nest(rec, side: "pngRight")
            let ly = left["irisYMatchesTarget"] as? Bool ?? false
            let ry = right["irisYMatchesTarget"] as? Bool ?? false
            let lx = left["irisXMatchesTarget"] as? Bool ?? false
            let rx = right["irisXMatchesTarget"] as? Bool ?? false
            let lIris = pair(left["pngIris"])
            let rIris = pair(right["pngIris"])
            if lIris == nil || rIris == nil { measured = false; yMatch = false; xMatch = false }
            if !ly || !ry { yMatch = false }
            if !lx || !rx { xMatch = false }
            let s = nest(rec, side: "shellCenters")
            if let ls = pair(s["left"]), let rs = pair(s["right"]) {
                shells.append(contentsOf: [ls, rs])
            }
            if name == "default-movies", let l = lIris, let r = rIris { defaultIris = (l, r) }
            if name == "window-exit-returns-default", let l = lIris, let r = rIris { offIris = (l, r) }
            frameNotes.append([
                "name": name,
                "leftYMatches": ly,
                "rightYMatches": ry,
                "leftXMatches": lx,
                "rightXMatches": rx,
                "pngLeftIris": left["pngIris"] as Any,
                "pngRightIris": right["pngIris"] as Any,
                "pngLeftUnit": left["pngIrisUnit"] as Any,
                "pngRightUnit": right["pngIrisUnit"] as Any
            ])
        }

        var shellFixed = true
        let expectedL: [Double] = [VectorEyeSpec.left.shell.center.x, VectorEyeSpec.left.shell.center.y]
        let expectedR: [Double] = [VectorEyeSpec.right.shell.center.x, VectorEyeSpec.right.shell.center.y]
        if shells.count >= 2 {
            for i in stride(from: 0, to: shells.count, by: 2) {
                if abs(shells[i][0] - expectedL[0]) > 0.5 || abs(shells[i][1] - expectedL[1]) > 0.5 { shellFixed = false }
                if i + 1 < shells.count {
                    if abs(shells[i+1][0] - expectedR[0]) > 0.5 || abs(shells[i+1][1] - expectedR[1]) > 0.5 { shellFixed = false }
                }
            }
        } else {
            shellFixed = false
        }

        var offMatches = false
        var offDelta: [String: Any] = [:]
        if let d = defaultIris, let o = offIris {
            let dl = hypot(d.0[0] - o.0[0], d.0[1] - o.0[1])
            let dr = hypot(d.1[0] - o.1[0], d.1[1] - o.1[1])
            offMatches = dl <= 8 && dr <= 8
            offDelta = ["leftPx": dl, "rightPx": dr, "tolerancePx": 8]
        }

        let passed = measured && yMatch && xMatch && shellFixed && offMatches
        let report: [String: Any] = [
            "note": "End-to-end measurements on cacheDisplay PNGs (canvas y-down). Iris vs sclera (globe) center, not pose JSON alone. Target below ⇒ png unitY > 0.",
            "passed": passed,
            "allFramesIrisYMatchesTarget": yMatch,
            "allFramesIrisXMatchesTarget": xMatch,
            "bothEyesMeasuredOnEveryFrame": measured,
            "shellCentersUnchangedAtDocumentedPlacement": shellFixed,
            "windowExitPNGMatchesDefaultMovies": offMatches,
            "windowExitDelta": offDelta,
            "expectedLeftShell": expectedL,
            "expectedRightShell": expectedR,
            "frames": frameNotes
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("gaze-png-assertions.json"))
        if passed {
            fputs("gaze-png-assertions: PASSED\n", stderr)
        } else {
            fputs("gaze-png-assertions: FAILED — see gaze-png-assertions.json\n", stderr)
        }
    }

    private static func overlayText(point: Point2D, eye: EyePresentation, sector: String) -> String {
        String(
            format: "ptr (%.0f, %.0f)  irisL(%.1f, %.1f)  irisR(%.1f, %.1f)  faceL %.2f  %@",
            point.x, point.y,
            eye.leftPupilOffset.x, eye.leftPupilOffset.y,
            eye.rightPupilOffset.x, eye.rightPupilOffset.y,
            eye.leftPose.facing,
            sector
        )
    }

    private static func render(session: InteractionSession, scale: CGFloat, eyeFrames: EyeFrameDriver? = nil,
                               logicalSize: NSSize = NSSize(width: 1200, height: 900)) throws -> NSBitmapImageRep {
        let logicalWidth = logicalSize.width, logicalHeight = logicalSize.height
        // Offscreen frames are initialized from the session's current target
        // (DemoRootView snaps pupil offsets in init). Do not write
        // accessibilityReduceMotion — that key is not writable on macOS 13.
        let root = DemoRootView(snapshot: session.snapshot, session: session, eyeFrames: eyeFrames)
            .frame(width: logicalWidth, height: logicalHeight)
            .background(Color.clear)
        let host = ClearHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.frame = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()

        let pixelsW = Int(logicalWidth * scale)
        let pixelsH = Int(logicalHeight * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw EvidenceError.bitmapFailed("alloc")
        }
        rep.size = NSSize(width: logicalWidth, height: logicalHeight)
        if let data = rep.bitmapData {
            memset(data, 0, rep.bytesPerRow * pixelsH)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private static func writeAnnotated(
        _ rep: NSBitmapImageRep,
        name: String,
        scale: CGFloat,
        caption: String,
        extra: String?,
        to directory: URL
    ) throws {
        guard let raw = rep.representation(using: .png, properties: [:]) else {
            throw EvidenceError.bitmapFailed(name)
        }
        try raw.write(to: directory.appendingPathComponent("\(name).png"))
        let banner: CGFloat = 56
        let pixelsW = Int(logicalWidth * scale)
        let pixelsH = Int((logicalHeight + banner) * scale)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw EvidenceError.bitmapFailed(name + "-labeled")
        }
        out.size = NSSize(width: logicalWidth, height: logicalHeight + banner)
        let ctx = NSGraphicsContext(bitmapImageRep: out)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.translateBy(x: 0, y: logicalHeight + banner)
        ctx.cgContext.scaleBy(x: 1, y: -1)
        NSColor(calibratedRed: 0.18, green: 0.07, blue: 0.06, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: logicalWidth, height: banner).fill()
        let title = "\(evidenceCaption)  ·  \(caption)"
        let sizeLine = String(
            format: "逻辑 %.0f×%.0f pt  ·  像素 %.0f×%.0f  ·  scale %.1f  ·  %@",
            logicalWidth, logicalHeight, logicalWidth * scale, logicalHeight * scale, scale, extra ?? ""
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)
        ]
        (title as NSString).draw(at: NSPoint(x: 12, y: 30), withAttributes: attrs)
        (sizeLine as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: small)
        if let cg = rep.cgImage {
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: banner + logicalHeight)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.draw(cg, in: NSRect(x: 0, y: banner, width: logicalWidth, height: logicalHeight))
            ctx.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else {
            throw EvidenceError.bitmapFailed(name + "-labeled")
        }
        try png.write(to: directory.appendingPathComponent("\(name)-labeled.png"))
    }

    private static func writeCheckerComposite(_ rep: NSBitmapImageRep, name: String, scale: CGFloat, to directory: URL) throws {
        let pixelsW = Int(logicalWidth * scale)
        let pixelsH = Int(logicalHeight * scale)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw EvidenceError.bitmapFailed(name) }
        out.size = NSSize(width: logicalWidth, height: logicalHeight)
        let ctx = NSGraphicsContext(bitmapImageRep: out)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cell: CGFloat = 24
        for y in stride(from: 0, to: logicalHeight, by: cell) {
            for x in stride(from: 0, to: logicalWidth, by: cell) {
                let odd = (Int(x / cell) + Int(y / cell)) % 2 == 0
                (odd ? NSColor(calibratedWhite: 0.82, alpha: 1) : NSColor(calibratedWhite: 0.62, alpha: 1)).setFill()
                NSRect(x: x, y: y, width: cell, height: cell).fill()
            }
        }
        if let cg = rep.cgImage {
            ctx.cgContext.draw(cg, in: NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight))
        }
        let caption = "\(evidenceCaption)  ·  棋盘格衬底；实心珊瑚板若覆盖该处则格子不可见"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.05, blue: 0.05, alpha: 1),
            .backgroundColor: NSColor(calibratedWhite: 1, alpha: 0.82)
        ]
        (caption as NSString).draw(at: NSPoint(x: 12, y: logicalHeight - 28), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else {
            throw EvidenceError.bitmapFailed(name)
        }
        try png.write(to: directory.appendingPathComponent(name))
    }

    private static func writeAlphaReport(_ rep: NSBitmapImageRep, scale: CGFloat, to directory: URL) throws {
        // View space and this NSBitmapImageRep are both y-down (top-left origin),
        // matching the saved PNG / PIL. A previous y-up flip sampled the platter
        // face instead of the top of the frame (064745 JSON vs PNG mismatch).
        // View is 1200×900; canvas is 2400×1800 (×2).
        func sample(canvasX: Double, canvasY: Double) -> [String: Any] {
            let viewX = canvasX / 2
            let viewY = canvasY / 2
            let px = Int((viewX * Double(scale)).rounded())
            let py = Int((viewY * Double(scale)).rounded())
            let cx = min(max(px, 0), Int(logicalWidth * scale) - 1)
            let cy = min(max(py, 0), Int(logicalHeight * scale) - 1)
            let color = rep.colorAt(x: cx, y: cy)
            let a = color?.alphaComponent ?? -1
            let alpha = Int((a * 255).rounded())
            return [
                "canvasPt": [canvasX, canvasY],
                "viewPt": [viewX, viewY],
                "bitmapPt": [cx, cy],
                "alpha": alpha,
                "rgba": [
                    Int(((color?.redComponent ?? -1) * 255).rounded()),
                    Int(((color?.greenComponent ?? -1) * 255).rounded()),
                    Int(((color?.blueComponent ?? -1) * 255).rounded()),
                    alpha
                ]
            ]
        }
        func attach(_ base: [String: Any], name: String, expect: String) -> [String: Any] {
            var d = base
            d["name"] = name
            d["expect"] = expect
            return d
        }
        // Solid lips / board below lipMinY (design y=348). Not the removed top wash.
        let boardPoints: [(String, Double, Double)] = [
            ("left-lip-band-200,450", 200, 450),
            ("right-lip-band-2200,450", 2200, 450)
        ]
        var boardSamples: [[String: Any]] = []
        var boardOpaque = 0
        for (name, x, y) in boardPoints {
            let s = attach(sample(canvasX: x, canvasY: y), name: name, expect: "alpha=255 (solid coral lips/board)")
            if (s["alpha"] as? Int) == 255 { boardOpaque += 1 }
            boardSamples.append(s)
        }
        // Above lipMinY: extra top wash removed; window background should be clear.
        let aboveLipPoints: [(String, Double, Double)] = [
            ("above-lips-80,80", 80, 80),
            ("above-lips-200,200", 200, 200),
            ("above-lips-2300,200", 2300, 200)
        ]
        var aboveLipSamples: [[String: Any]] = []
        var aboveZero = 0
        for (name, x, y) in aboveLipPoints {
            let s = attach(sample(canvasX: x, canvasY: y), name: name, expect: "alpha=0 (above lipMinY, no full-canvas wash)")
            if (s["alpha"] as? Int) == 0 { aboveZero += 1 }
            aboveLipSamples.append(s)
        }
        let platterPoints: [(String, Double, Double)] = [
            ("platter-400,1200", 400, 1200),
            ("platter-1200,1400", 1200, 1400)
        ]
        var platterSamples: [[String: Any]] = []
        for (name, x, y) in platterPoints {
            platterSamples.append(attach(sample(canvasX: x, canvasY: y), name: name, expect: "opaque (>0) platter face"))
        }
        let payload: [String: Any] = [
            "note": "\(evidenceCaption)  ·  叠唇/盘后板可见点期望 alpha=255。lipMinY=348 以上为去掉的额外顶背景，期望 alpha=0（以设计坐标为准，不使用截图像素）。",
            "logicalPoints": [logicalWidth, logicalHeight],
            "canvasPoints": [2400, 1800],
            "lipMinY": 348,
            "backingScaleFactor": scale,
            "pixelSize": [logicalWidth * scale, logicalHeight * scale],
            "boardSamples": boardSamples,
            "boardOpaqueCount": boardOpaque,
            "boardCount": boardPoints.count,
            "allBoardSamplesAlpha255": boardOpaque == boardPoints.count,
            "aboveLipSamples": aboveLipSamples,
            "aboveLipZeroCount": aboveZero,
            "aboveLipCount": aboveLipPoints.count,
            "allAboveLipSamplesAlphaZero": aboveZero == aboveLipPoints.count,
            "platterSamples": platterSamples
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("alpha-samples-coral-board-and-eye-bounds.json"))
    }

    private static func writeEyeBoundsReport(to directory: URL) throws {
        let layout = SemicircleLayout.selectedBase
        let left = layout.eyeExclusions[0]
        let right = layout.eyeExclusions[1]
        let margin = EyePlacement.topSafetyMargin
        func pack(_ e: AxisAlignedEllipse, name: String) -> [String: Any] {
            let inFrame = e.minX >= 0 && e.maxX <= layout.canvasWidth && e.minY >= margin && e.maxY <= layout.canvasHeight
            return [
                "name": name,
                "center": [e.center.x, e.center.y],
                "radiusX": e.radiusX,
                "radiusY": e.radiusY,
                "minX": e.minX, "minY": e.minY, "maxX": e.maxX, "maxY": e.maxY,
                "topAtOrAboveSafetyMargin": e.minY >= margin,
                "fullyInsideCanvasWithTopMargin": inFrame
            ]
        }
        let span = EyePlacement.binocularSpan(layout: layout)
        let payload: [String: Any] = [
            "note": "\(evidenceCaption)  ·  几何眼轮廓（命中排除椭圆与绘制壳同步）。左眼顶由 −32 升到 24，半径未改，组合宽 1272/2400≈53%。",
            "canvas": [layout.canvasWidth, layout.canvasHeight],
            "eyesOrigin": [SelectedBaseArtwork.eyesOrigin.x, SelectedBaseArtwork.eyesOrigin.y],
            "canvasLift": EyePlacement.canvasLift,
            "topSafetyMargin": margin,
            "left": pack(left, name: "left"),
            "right": pack(right, name: "right"),
            "binocularSpan": span,
            "visibleDiscWidth": layout.canvasWidth,
            "spanOverVisibleDiscWidth": span / layout.canvasWidth,
            "spanInSpecRange1270to1277": span >= 1270 && span <= 1277,
            "bothEyesFullyInFrame": (left.minY >= margin && right.minY >= margin
                && left.minX >= 0 && right.maxX <= layout.canvasWidth
                && left.maxY <= layout.canvasHeight && right.maxY <= layout.canvasHeight)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("eye-bounds.json"))
    }

    private static func writeContactSheet(images: [NSBitmapImageRep], records: [[String: Any]], scale: CGFloat, to url: URL) throws {
        let cols = min(4, max(images.count, 1))
        let rows = Int(ceil(Double(images.count) / Double(cols)))
        let cellW = logicalWidth / 2
        let cellH = logicalHeight / 2
        let width = cellW * CGFloat(cols)
        let height = cellH * CGFloat(rows) + 40
        let pixelsW = Int(width * scale)
        let pixelsH = Int(height * scale)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw EvidenceError.bitmapFailed("contact") }
        out.size = NSSize(width: width, height: height)
        let ctx = NSGraphicsContext(bitmapImageRep: out)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        (evidenceCaption as NSString).draw(
            at: NSPoint(x: 12, y: height - 28),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        for (i, rep) in images.enumerated() {
            let c = i % cols
            let r = i / cols
            let rect = NSRect(x: CGFloat(c) * cellW, y: height - 40 - CGFloat(r + 1) * cellH, width: cellW, height: cellH)
            if let cg = rep.cgImage {
                ctx.cgContext.draw(cg, in: rect)
            }
            let label = (records[i]["name"] as? String) ?? "\(i)"
            (label as NSString).draw(
                at: NSPoint(x: rect.minX + 8, y: rect.minY + 6),
                withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white,
                    .backgroundColor: NSColor(calibratedWhite: 0, alpha: 0.55)
                ]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else {
            throw EvidenceError.bitmapFailed("contact")
        }
        try png.write(to: url)
    }

    private static func writeGIF(images: [NSBitmapImageRep], scale: CGFloat, to url: URL) throws {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil)
        guard let dest else { throw EvidenceError.bitmapFailed("gif") }
        let frameProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.45]]
        let fileProps: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
        for rep in images {
            guard let cg = rep.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }
        if !CGImageDestinationFinalize(dest) {
            throw EvidenceError.bitmapFailed("gif-finalize")
        }
        _ = scale
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f.string(from: Date())
    }

    enum EvidenceError: Error {
        case bitmapFailed(String)
    }
}

final class BorderlessDemoWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
