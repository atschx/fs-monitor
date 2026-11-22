#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI
import DemoFirstScreenCore
import FolderSnapshotAdapter

/// Root view. Pointer and keyboard input go through an AppKit host so the
/// deployment target can stay macOS 13 (no onContinuousHover / onKeyPress).
enum DemoRenderPart:Equatable {case normal,withoutEyes,foregroundOnly}

struct DemoRootView: View {
    let renderPart:DemoRenderPart
    let snapshot: DemoSnapshot
    @State private var session: InteractionSession
    @State private var pointerInsideWindow = true
    @ObservedObject private var eyeFrames: EyeFrameDriver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: DemoSnapshot, session: InteractionSession? = nil, eyeFrames: EyeFrameDriver? = nil, renderPart:DemoRenderPart = .normal) {
        self.renderPart=renderPart
        self.snapshot = snapshot
        let initial = session ?? InteractionSession(snapshot: snapshot)
        _session = State(initialValue: initial)
        // Live launch starts with the pointer considered inside the window but no
        // coordinate yet (eyes at the default largest-sector gaze). Evidence
        // passes a pre-moved session and snaps the shared target so cacheDisplay
        // is not stuck at default.
        let inside = session != nil ? (initial.state.pointerLocation != nil) : true
        let frame = FramePresentation.make(
            session: initial,
            motion: MotionPolicy.reduced,
            pointerInsideWindow: inside
        )
        _pointerInsideWindow = State(initialValue: inside)
        _eyeFrames = ObservedObject(wrappedValue: eyeFrames ?? EyeFrameDriver(target: frame.eye.resolvedTarget, frozen: true, source: .inAppEvidence))
    }

    var motion: MotionPolicy { MotionPolicy(reduceMotion: reduceMotion) }

    /// Read-only. This demo never writes user accessibility display settings.
    var glass: GlassLikePolicy {
        GlassLikePolicy(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    var presentation: FramePresentation {
        FramePresentation.make(session: session, motion: motion, pointerInsideWindow: pointerInsideWindow)
    }

    var body: some View {
        GeometryReader { geo in
            let map = WindowCanvasMap(width: geo.size.width, height: geo.size.height)
            ZStack(alignment: .topLeading) {
                Color.clear
                ZStack(alignment: .topLeading) {
                    if renderPart != .foregroundOnly {
                        platter(in: CGSize(width: 2400 * map.scale, height: 1800 * map.scale))
                    }
                    if renderPart == .normal,let gpu=eyeFrames.gpu {
                        IntegratedMetalLayer(gpu:gpu).frame(maxWidth:.infinity,maxHeight:.infinity).allowsHitTesting(false)
                    }
                    if snapshot.folderLogicalProof != nil {realCardLeaderLines}
                    defaultSectorLabels
                    infoOverlay
                }
                .frame(width: 2400 * map.scale, height: 1800 * map.scale)
                .offset(x: map.origin.x, y: map.origin.y)
                EventCatcher(
                    onMove: { location in
                        pointerInsideWindow = true
                        apply(moveTo: map.canvasPoint(Point2D(x: location.x, y: location.y)))
                    },
                    onExit: {
                        pointerInsideWindow = false
                        session.pointerExitedVisibleArea()
                        retargetEyes()
                    },
                    onClick: { location in
                        pointerInsideWindow = true
                        apply(clickAt: map.canvasPoint(Point2D(x: location.x, y: location.y)))
                    },
                    onKey: { key in handle(key); retargetEyes() },
                    onWindowFocus: { focused in
                        if focused { session.windowGainedFocus() }
                        else { session.windowLostFocus() }
                        // Focus changes info P/K, never pretend the pointer left.
                        retargetEyes()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .background(Color.clear)
        .onChange(of: reduceMotion) { _ in retargetEyes() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let info = presentation.info
        // Omit identityText on the example path so VoiceOver does not reintroduce the removed badge.
        let parts: [String?] = [
            info.name,
            info.sizeText,
            info.timeText,
            info.insufficiencyText,
            info.activityText,
            info.staleResultText,
            info.onScreenIdentityText
        ]
        return parts
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "。")
    }

    private func apply(moveTo point: Point2D) {
        // Do not wrap the whole session mutation in withAnimation: that would
        // restart from a prior value or add a lag to every mouseMoved.
        session.pointerMoved(to: point)
        retargetEyes()
    }

    private func apply(clickAt point: Point2D) {
        session.pointerClicked(at: point)
        retargetEyes()
    }

    /// Driver has a real monotonic frame clock; no implicit animation around
    /// an opaque CPU image, and no resetting duration per mouse event.
    private func retargetEyes() {
        eyeFrames.retarget(presentation.eye.resolvedTarget, reduced: reduceMotion)
    }

    private func handle(_ key: EventCatcher.Key) {
        switch key {
        case .next: session.moveKeyboardFocus(.next)
        case .previous: session.moveKeyboardFocus(.previous)
        case .confirm: session.enterPressed()
        }
    }

    private func platter(in size: CGSize) -> some View {
        let layout = SemicircleLayout.selectedBase
        let highlightID = presentation.highlightID
        let sectors = presentation.isChartable ? session.chartability.sectors : []
        let glass = self.glass
        func sectorColor(id: String) -> Color {
            if highlightID == id {
                return Color(hex: Palette.hoverTeal)
            }
            switch id {
            case "Movies": return Color(hex: Palette.system)
            case "Archives": return Color(hex: Palette.applications)
            case "Documents": return Color(hex: Palette.usersRest)
            case "Pictures": return Color(hex: Palette.library)
            case "Projects": return Color(hex: Palette.exampleProjects)
            case "Applications": return Color(hex: Palette.applications)
            case "Library": return Color(hex: Palette.library)
            case "System": return Color(hex: Palette.system)
            case "Users": return Color(hex: Palette.usersRest)
            default:
                if snapshot.folderLogicalProof != nil, let i=sectors.firstIndex(where:{$0.id==id}) {
                    return Color(hex:[Palette.system,Palette.applications,Palette.usersRest,Palette.library,Palette.exampleProjects][i % 5])
                }
                return Color(hex: Palette.undividedFace)
            }
        }
        return Canvas { context, canvasSize in
            let drawBegan = ProcessInfo.processInfo.systemUptime
            defer {
                // Command encoding only, NOT GPU present time / GUI frame rate.
                if Thread.isMainThread {
                    LocalDiagnostics.shared.record("canvas-encode", source: eyeFrames.diagnosticRenderSource,
                        values: ["encodeMs": (ProcessInfo.processInfo.systemUptime-drawBegan)*1000])
                }
            }
            let sx = canvasSize.width / layout.canvasWidth
            let sy = canvasSize.height / layout.canvasHeight
            let scale = min(sx, sy)
            func rect(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> CGRect {
                CGRect(x: minX * sx, y: minY * sy, width: (maxX - minX) * sx, height: (maxY - minY) * sy)
            }
            func oval(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Path {
                Path(ellipseIn: rect(minX, minY, maxX, maxY))
            }
            func ellipsePath(_ e: AxisAlignedEllipse) -> Path {
                oval(e.minX, e.minY, e.maxX, e.maxY)
            }
            func rounded(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double, corner: Double) -> Path {
                Path(roundedRect: rect(minX, minY, maxX, maxY), cornerRadius: corner * scale)
            }

            // Solid coral board = stacked rounded lips only (2× draw_review
            // L18–21). The former full-canvas wash above lipMinY is not drawn
            // (Albert 06:43: extra top background removed; lips and the board
            // behind/below them to the disc edge are kept). Eyes stay in front.
            for layer in CoralBackplate.layers {
                let path = rounded(layer.minX, layer.minY, layer.maxX, layer.maxY, corner: layer.corner)
                context.fill(path, with: .color(Color(hex: layer.fillHex)))
                if let stroke = layer.strokeHex, layer.lineWidth > 0 {
                    context.stroke(path, with: .color(Color(hex: stroke)), lineWidth: layer.lineWidth * scale)
                }
            }

            context.fill(oval(-268, 576, 2668, 2460), with: .color(Color(hex: Palette.rimShadow)))
            context.fill(oval(-268, 530, 2668, 2414), with: .color(Color(hex: Palette.rimCool)))
            context.stroke(oval(-268, 530, 2668, 2414), with: .color(Color(hex: Palette.rimCoolStroke)), lineWidth: 8 * scale)

            let center = CGPoint(x: layout.center.x * sx, y: layout.center.y * sy)
            let mathR = layout.radius * scale
            if sectors.isEmpty {
                var face = Path()
                face.move(to: center)
                face.addArc(center: center, radius: mathR, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                face.closeSubpath()
                var ctx = context
                ctx.clip(to: oval(layout.platterClipEllipse.minX, layout.platterClipEllipse.minY, layout.platterClipEllipse.maxX, layout.platterClipEllipse.maxY))
                ctx.fill(face, with: .color(Color(hex: Palette.undividedFace)))
            } else {
                var ctx = context
                ctx.clip(to: oval(layout.platterClipEllipse.minX, layout.platterClipEllipse.minY, layout.platterClipEllipse.maxX, layout.platterClipEllipse.maxY))
                for sector in sectors {
                    var slice = Path()
                    slice.move(to: center)
                    slice.addArc(
                        center: center,
                        radius: mathR,
                        startAngle: .degrees(sector.startDegrees),
                        endAngle: .degrees(sector.endDegrees),
                        clockwise: false
                    )
                    slice.closeSubpath()
                    ctx.fill(slice, with: .color(sectorColor(id: sector.id)))
                }
            }

            if let highlightID, glass.hoverGloss > 0 || glass.hoverShade > 0,
               let sector = sectors.first(where: { $0.id == highlightID }) {
                var gloss = context
                gloss.clip(to: oval(layout.platterClipEllipse.minX, layout.platterClipEllipse.minY, layout.platterClipEllipse.maxX, layout.platterClipEllipse.maxY))
                var slice = Path()
                slice.move(to: center)
                slice.addArc(
                    center: center,
                    radius: mathR,
                    startAngle: .degrees(sector.startDegrees),
                    endAngle: .degrees(sector.endDegrees),
                    clockwise: false
                )
                slice.closeSubpath()
                gloss.clip(to: slice)
                let mid = (sector.startDegrees + sector.endDegrees) / 2
                let rad = mid * Double.pi / 180
                let gx = center.x + CGFloat(cos(rad) * 900 * scale)
                let gy = center.y + CGFloat(sin(rad) * 900 * scale)
                gloss.fill(
                    slice,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(glass.hoverGloss),
                            Color.clear,
                            Color.black.opacity(glass.hoverShade)
                        ]),
                        startPoint: CGPoint(x: gx, y: gy),
                        endPoint: center
                    )
                )
            }

            if glass.platterGlow > 0 {
                var glow = context
                glow.clip(to: oval(layout.platterClipEllipse.minX, layout.platterClipEllipse.minY, layout.platterClipEllipse.maxX, layout.platterClipEllipse.maxY))
                let glowRect = rect(910 - 1140, 980 - 860, 910 + 1140, 980 + 860)
                glow.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(glass.platterGlow), Color.clear]),
                        center: CGPoint(x: 910 * sx, y: 980 * sy),
                        startRadius: 0,
                        endRadius: 1140 * scale
                    )
                )
            }

            context.stroke(oval(-188, 542, 2588, 2326), with: .color(Color(hex: Palette.rimHairline)), lineWidth: 6 * scale)
            if glass.rimSpecularity > 0 {
                context.stroke(
                    oval(-200, 524, 2600, 2338),
                    with: .color(Color.white.opacity(glass.rimSpecularity)),
                    lineWidth: 3 * scale
                )
            }

            // Natural per-eye contact shadows. The former wide dark-red oval
            // (530,560)–(1914,754) is the residual stain being removed.
            for spec in [VectorEyeSpec.left, VectorEyeSpec.right] {
                let s = SphereGaze.contactShadow(spec: spec)
                var shadow = context
                shadow.addFilter(.blur(radius: 18 * scale))
                shadow.fill(
                    oval(s.minX, s.minY, s.maxX, s.maxY),
                    with: .color(Color(red: 110 / 255, green: 64 / 255, blue: 42 / 255).opacity(0.32))
                )
            }

            if renderPart == .normal,eyeFrames.gpu == nil,let pair = eyeFrames.pair {
                drawEyeImage(pair.left, spec: .left, context: &context, sx: sx, sy: sy)
                drawEyeImage(pair.right, spec: .right, context: &context, sx: sx, sy: sy)
            }

            var hubShadow = context
            hubShadow.addFilter(.blur(radius: 14 * scale))
            hubShadow.fill(
                oval(940 + 45, 1665 + 100, 940 + 475, 1665 + 248),
                with: .color(Color(red: 55 / 255, green: 48 / 255, blue: 34 / 255).opacity(100 / 255))
            )
            if let image = ArtworkImages.hub {
                let origin = SelectedBaseArtwork.hubOrigin
                let size = SelectedBaseArtwork.hubSize
                context.draw(Image(nsImage: image), in: rect(origin.x, origin.y, origin.x + size.x, origin.y + size.y))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.clear)
        .allowsHitTesting(false)
    }

    private func drawEyeImage(_ image: NSImage, spec: VectorEyeSpec,
                              context: inout GraphicsContext, sx: Double, sy: Double) {
        let r = SphereEyeRaster.canvasRect(spec: spec)
        context.draw(Image(nsImage: image), in: CGRect(x: r.minX*sx, y: r.minY*sy,
                     width: r.width*sx, height: r.height*sy))
    }

    private var defaultSectorLabels: some View {
        let labels = presentation.visibleSectorCoreLabels
        let layout = SemicircleLayout.selectedBase
        return GeometryReader { geo in
            let sx = geo.size.width / layout.canvasWidth
            let sy = geo.size.height / layout.canvasHeight
            let scale = min(sx, sy)
            let glass = self.glass
            ZStack {
                ForEach(labels, id: \.id) { label in
                    let box=measuredRealCards[label.id]
                    VStack(alignment: .leading, spacing: 4 * sy) {
                        Text(label.name).lineLimit(snapshot.folderLogicalProof != nil ? 2:nil).help(label.name)
                            .font(.system(size: 44 * scale, weight: .semibold))
                        Text(snapshot.folderLogicalProof != nil ? FolderAdapter.compactBytes(snapshot.items.first(where:{$0.id==label.id})?.knownBytes ?? 0):label.sizeText)
                            .font(.system(size: 36 * scale, weight: .regular))
                    }
                    .frame(width:box.map{($0.width-32)*sx},height:box.map{($0.height-20)*sy},alignment:.leading)
                    .foregroundColor(Color(red: glass.infoInkRed, green: glass.infoInkGreen, blue: glass.infoInkBlue))
                    .padding(.horizontal, 16 * sx)
                    .padding(.vertical, 10 * sy)
                    .background(
                        RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                            .fill(Color(hex: glass.infoFillHex).opacity(glass.infoFillOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                            .stroke(Color.white.opacity(glass.infoStrokeOpacity), lineWidth: 1 * scale)
                    )
                    .position(x: (box?.center.x ?? label.center.x) * sx, y: (box?.center.y ?? label.center.y) * sy)
                }
            }
        }
        .allowsHitTesting(false)
    }

    var measuredRealCards:[String:CardPlacement] {
        guard snapshot.folderLogicalProof != nil else{return [:]}
        let f=presentation;var cards=[MeasuredCard]()
        if f.infoPlacement.isVisible,!f.info.isOverview,let id=f.infoPlacement.identityID {
            cards.append(MeasuredCard(id:id,anchor:f.infoPlacement.center,width:600,height:390))
        }
        for label in f.visibleSectorCoreLabels {
            let font=NSFont.systemFont(ofSize:44,weight:.semibold)
            let rect=(label.name as NSString).boundingRect(with:NSSize(width:500,height:120),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font])
            let bytes=FolderAdapter.compactBytes(snapshot.items.first(where:{$0.id==label.id})?.knownBytes ?? 0)
            let size=(bytes as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:36)])
            cards.append(MeasuredCard(id:label.id,anchor:label.center,width:min(560,max(rect.width,size.width)+48),height:min(220,rect.height+size.height+44)))
        }
        return CardAvoidance.layout(cards)
    }
    private var realCardLeaderLines:some View {
        GeometryReader{geo in
            let boxes=measuredRealCards,sx=geo.size.width/2400,sy=geo.size.height/1800
            Canvas{context,_ in
                for box in boxes.values where box.needsLeader {
                    var p=Path();p.move(to:CGPoint(x:box.anchor.x*sx,y:box.anchor.y*sy));p.addLine(to:CGPoint(x:box.center.x*sx,y:box.center.y*sy))
                    context.stroke(p,with:.color(Color(hex:"#58787a").opacity(0.7)),lineWidth:max(0.6,2*sx))
                }
            }
        }.allowsHitTesting(false)
    }

    private var infoOverlay: some View {

        let info = presentation.info
        let placement = presentation.infoPlacement
        let layout = SemicircleLayout.selectedBase
        return GeometryReader { geo in
            let sx = geo.size.width / layout.canvasWidth
            let sy = geo.size.height / layout.canvasHeight
            let scale = min(sx, sy)
            ZStack(alignment: .topLeading) {
                Color.clear
                if placement.isVisible, !info.isOverview {
                    let box=placement.identityID.flatMap{measuredRealCards[$0]}
                    let glass = self.glass
                    VStack(alignment: .leading, spacing: 6 * sy) {
                        Text(info.name).lineLimit(snapshot.folderLogicalProof != nil ? 2:nil).help(info.name)
                            .font(.system(size: 58 * scale, weight: .semibold))
                        Text(snapshot.folderLogicalProof != nil ? FolderAdapter.compactBytes(info.sizeBytes ?? 0):info.sizeText)
                            .font(.system(size: 54 * scale, weight: .regular))
                        Text(info.timeText)
                            .font(.system(size: 36 * scale))
                        Text(info.activityText)
                            .font(.system(size: 36 * scale))
                    }
                    .frame(width:box.map{($0.width-44)*sx},height:box.map{($0.height-32)*sy},alignment:.leading)
                    .foregroundColor(Color(red: glass.infoInkRed, green: glass.infoInkGreen, blue: glass.infoInkBlue))
                    .padding(.horizontal, 22 * sx)
                    .padding(.vertical, 16 * sy)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                                .fill(Color(hex: glass.infoFillHex).opacity(glass.infoFillOpacity))
                            if glass.infoHighlight > 0 {
                                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(glass.infoHighlight), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                            .stroke(Color.white.opacity(glass.infoStrokeOpacity), lineWidth: 1.2 * scale)
                    )
                    .position(x:(box?.center.x ?? placement.center.x)*sx,y:(box?.center.y ?? placement.center.y)*sy)
                    .animation(
                        motion.allowsInterpolation
                            ? .easeOut(duration: Double(motion.infoDurationMs) / 1000.0)
                            : nil,
                        value: placement.identityID
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }


}

/// AppKit event surface for macOS 13: mouse move/click, Tab/arrows/Return, window key-state.
struct EventCatcher: NSViewRepresentable {
    enum Key {
        case next, previous, confirm
    }

    var onMove: (CGPoint) -> Void
    var onExit: () -> Void
    var onClick: (CGPoint) -> Void
    var onKey: (Key) -> Void
    var onWindowFocus: (Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onMove = onMove
        view.onExit = onExit
        view.onClick = onClick
        view.onKey = onKey
        view.onWindowFocus = onWindowFocus
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
        nsView.onClick = onClick
        nsView.onKey = onKey
        nsView.onWindowFocus = onWindowFocus
    }

    final class CatcherView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?
        var onClick: ((CGPoint) -> Void)?
        var onKey: ((Key) -> Void)?
        var onWindowFocus: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?
        private var resignObs: Any?
        private var becomeObs: Any?
        private var lastLayout: [Double] = []

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            window?.makeFirstResponder(self)
            installTracking()
            installFocusObservers()
        }

        override func layout() {
            super.layout()
            installTracking()
            let map = WindowCanvasMap(width: bounds.width, height: bounds.height)
            let fingerprint = [Double(bounds.width), Double(bounds.height), Double(window?.backingScaleFactor ?? 1)]
            if fingerprint != lastLayout {
                lastLayout = fingerprint
                LocalDiagnostics.shared.record("layout", source: .view,
                    values: ["width": bounds.width, "height": bounds.height,
                             "backingScale": window?.backingScaleFactor ?? 1,
                             "canvasScale": map.scale,
                             "rasterToDeviceScale": map.scale * (window?.backingScaleFactor ?? 1)], flags: ["attachedToWindow": window != nil])
            }
        }

        private func installTracking() {
            // inVisibleRect tracks resizing itself. Rebuilding on every SwiftUI
            // layout could manufacture exits/enters while the pointer is still.
            guard tracking == nil else { return }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        private func installFocusObservers() {
            if let resignObs { NotificationCenter.default.removeObserver(resignObs) }
            if let becomeObs { NotificationCenter.default.removeObserver(becomeObs) }
            resignObs = nil; becomeObs = nil
            guard window != nil else { return } // never observe all app windows
            resignObs = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                LocalDiagnostics.shared.record("focus", source: .view, flags: ["key": false])
                IntegratedGPUEyes.localFocus(false)
                self?.onWindowFocus?(false)
            }
            becomeObs = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                LocalDiagnostics.shared.record("focus", source: .view, flags: ["key": true])
                self?.window?.makeFirstResponder(self)
                IntegratedGPUEyes.localFocus(true)
                self?.onWindowFocus?(true)
            }
        }

        deinit {
            if let resignObs { NotificationCenter.default.removeObserver(resignObs) }
            if let becomeObs { NotificationCenter.default.removeObserver(becomeObs) }
        }

        func recordGeometry(reason:String){
            guard let log=IntegratedGPUEyes.active?.log,let window,let content=window.contentView else{return}
            let origin=convert(CGPoint.zero,to:content)
            log.add(["type":"own-view-geometry","host":CACurrentMediaTime(),"reason":reason,"viewIdentity":String(describing:ObjectIdentifier(self)),"trackingIdentity":tracking.map{String(describing:ObjectIdentifier($0))} ?? "nil","bounds":[bounds.minX,bounds.minY,bounds.width,bounds.height],"viewOriginInContent":[origin.x,origin.y],"contentBounds":[content.bounds.minX,content.bounds.minY,content.bounds.width,content.bounds.height],"isKey":window.isKeyWindow,"isFlipped":isFlipped,"contentFlipped":content.isFlipped,"windowNumber":window.windowNumber])
        }
        private func recordPointer(_ event:NSEvent,source:String,decision:String,point:CGPoint,acceptedKind:String?){
            if let acceptedKind {IntegratedGPUEyes.noteInput(acceptedKind,event:event)}
            guard let log=IntegratedGPUEyes.active?.log,let window,let content=window.contentView else{return}
            let cp=content.convert(event.locationInWindow,from:nil)
            let details:[String:Any] = ["callback":source,"decision":decision,"eventTypeRaw":event.type.rawValue,"eventNumber":event.eventNumber,"eventWindowIsOwn":event.window === window,"eventWindowNil":event.window == nil,"viewIdentity":String(describing:ObjectIdentifier(self)),"trackingIdentity":tracking.map{String(describing:ObjectIdentifier($0))} ?? "nil","localWindowPoint":[point.x,point.y],"windowBasePoint":[event.locationInWindow.x,event.locationInWindow.y],"contentPoint":[cp.x,cp.y],"bounds":[bounds.minX,bounds.minY,bounds.width,bounds.height],"contentBounds":[content.bounds.minX,content.bounds.minY,content.bounds.width,content.bounds.height],"insideView":bounds.contains(point),"insideContent":content.bounds.contains(cp),"isKey":window.isKeyWindow]
            if let acceptedKind {var row=details;row["type"]="own-view-event";row["kind"]=acceptedKind;row["receivedHost"]=CACurrentMediaTime();row["rawNSEventTimestamp"]=event.timestamp;log.add(row)}
            else {var row=details;row["type"]="own-view-event-ignored";row["receivedHost"]=CACurrentMediaTime();row["rawNSEventTimestamp"]=event.timestamp;log.add(row)}
        }
        private func canvasPoint(from event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        private func deliver(_ event: NSEvent, kind: String, click: Bool = false) {
            // Only events delivered to THIS NSView/window. Drag capture may
            // continue outside; do not log outside coordinates or follow them.
            guard let ownWindow = window, event.window == nil || event.window === ownWindow else { return }
            let p = canvasPoint(from: event)
            guard bounds.contains(p) else {
                recordPointer(event,source:kind,decision:"exit-outside-delivery",point:p,acceptedKind:"exit-outside-delivery")
                LocalDiagnostics.shared.record("exit", source: .osLocal)
                onExit?(); return
            }
            LocalDiagnostics.shared.record(kind, source: .osLocal,
                values: ["x": p.x, "y": p.y, "width": bounds.width, "height": bounds.height],
                flags: ["key": window?.isKeyWindow ?? false])
            recordPointer(event,source:kind,decision:"inside-follow",point:p,acceptedKind:kind)
            if click { onClick?(p) } else { onMove?(p) }
        }
        override func mouseMoved(with event: NSEvent) { deliver(event, kind: "move") }
        override func mouseDragged(with event: NSEvent) { deliver(event, kind: "drag") }
        override func mouseEntered(with event: NSEvent) { deliver(event, kind: "enter") }
        override func mouseExited(with event: NSEvent) {
            guard let ownWindow = window, event.window == nil || event.window === ownWindow else { return }
            let p = canvasPoint(from: event)
            // A tracking-area/visibility exit is not automatically a WINDOW
            // exit. Keep gaze when the delivered local point is still inside.
            if bounds.contains(p) {
                recordPointer(event,source:"mouseExited",decision:"ignore-tracking-exit-inside-view",point:p,acceptedKind:nil)
                LocalDiagnostics.shared.record("tracking-exit-inside", source: .osLocal,
                    values: ["x": p.x, "y": p.y, "width": bounds.width, "height": bounds.height])
                return
            }
            recordPointer(event,source:"mouseExited",decision:"exit-outside-mouseExited",point:p,acceptedKind:"exit-outside-mouseExited")
            LocalDiagnostics.shared.record("exit", source: .osLocal)
            onExit?()
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            deliver(event, kind: "click", click: true)
        }

        override func keyDown(with event: NSEvent) {
            IntegratedGPUEyes.localKey()
            switch event.keyCode {
            case 48: // Tab
                onKey?(event.modifierFlags.contains(.shift) ? .previous : .next)
            case 123, 126: // left, up
                onKey?(.previous)
            case 124, 125: // right, down
                onKey?(.next)
            case 36, 76: // return, keypad enter
                onKey?(.confirm)
            default:
                super.keyDown(with: event)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.keyCode == 48 {
                onKey?(event.modifierFlags.contains(.shift) ? .previous : .next)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}

enum ArtworkImages {
    static func nsImage(named name: String) -> NSImage? {
        guard let url = DemoArtwork.url(named: name) else { return nil }
        return NSImage(contentsOf: url)
    }

    static var hub: NSImage? { nsImage(named: "d2-hub") }
}

final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
#endif
