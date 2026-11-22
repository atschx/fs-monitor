#if os(macOS)
import AppKit
import MetalKit
import QuartzCore
import DemoFirstScreenCore
import EyeStudySupport

/// Diagnostic storage is opt-in, finite, local to this study window. No monitor.
final class LocalStudyLog {
    let directory:URL
    private var rows:[[String:Any]]=[]
    private var dropped=0
    private var finished=false
    var phase="startup"
    var phaseMode="A"
    var phaseStart=0.0
    init(directory:URL){self.directory=directory}
    func add(_ row:[String:Any]) {
        guard !finished else{return}
        guard rows.count<10000 else{dropped+=1;return};var value=row;if value["phase"]==nil{value["phase"]=phase};if value["mode"]==nil{value["mode"]=phaseMode};rows.append(value)
    }
    func finish() {
        guard !finished else{return};finished=true
        let gpu=rows.filter{($0["type"] as? String)=="gpu-completed"}
        let submitted=rows.filter{($0["type"] as? String)=="submitted"}
        let presented=rows.filter{($0["type"] as? String)=="presented"}.sorted{($0["presentedHost"] as? Double ?? 0)<($1["presentedHost"] as? Double ?? 0)}
        let times=presented.compactMap{$0["presentedHost"] as? Double}.filter{$0>0}
        let intervals=zip(times.dropFirst(),times).map{($0-$1)*1000}
        let med=StudyMetrics.percentile(intervals,0.5)
        let jitter=med.map{m in intervals.map{abs($0-m)}} ?? []
        // First new-goal influence is a trajectory proxy, not a pixel measurement.
        var first:[String:[String:Any]]=[:]
        for row in presented {
            if let id=row["signalID"] as? Int,let influence=row["newGoalInfluenceHeadingUnits"] as? Double,influence>0.2,
               let elapsed=row["receiptToPresentedTrajectoryProxyMs"] as? Double,elapsed>=0,first[String(id)]==nil {
                first[String(id)]=["elapsedMs":elapsed,"source":row["signalKind"] ?? "unknown","frame":row["frame"] ?? 0]
            }
        }
        let summary:[String:Any] = ["recordCount":rows.count,"droppedAt10000Cap":dropped,
            "gpuComputePlusPresentPassMs":StudyMetrics.stats(gpu.compactMap{$0["gpuMs"] as? Double}),
            "cpuEncodeMs":StudyMetrics.stats(submitted.compactMap{$0["cpuEncodeMs"] as? Double}),
            "drawableWaitMs":StudyMetrics.stats(submitted.compactMap{$0["drawableWaitMs"] as? Double}),
            "commitCallMs":StudyMetrics.stats(submitted.compactMap{$0["commitCallMs"] as? Double}),
            "commitToGPUStartSanityOnlyMs":StudyMetrics.stats(gpu.compactMap{$0["commitToGPUStartSanityOnlyMs"] as? Double}),
            "presentedIntervalMs":StudyMetrics.stats(intervals),"absoluteIntervalDeviationFromMedianMs":StudyMetrics.stats(jitter),
            "goalDistanceAtEncodeHeadingUnits":StudyMetrics.stats(submitted.compactMap{$0["distanceToGoalHeadingUnits"] as? Double}),
            "zeroPresentedTimeCount":presented.filter{($0["presentedHost"] as? Double ?? 0)<=0}.count,
            "firstInfluencedPosePresentedProxiesBySignal":first,"gpuCommandBufferInFlightCap":1,"presentPendingDrawableDepthMeasured":false,
            "completionMainQueueWaitMs":StudyMetrics.stats(gpu.compactMap{$0["mainQueueWaitMs"] as? Double}),
            "settledPosePresentedProxies":presented.filter{$0["goalSettlePresentedProxyMs"] != nil},
            "submittedCount":submitted.count,"completedCount":gpu.count,"presentedCallbackCount":presented.count,
            "scope":"Only this App's view callbacks and GPU callbacks. Synthetic source labeled. No global input, OS screen capture or private content. Callbacks not received before finite cutoff remain unmatched; absence is NOT zero latency.",
            "clockBoundary":"Raw NSEvent timestamp kept separate; never subtracted. Host ordering checks are sanity observations, NOT rigorous clock calibration. Derived receipt/presentation values are trajectory proxies only.",
            "physicalInputToPhotonVerified":false,"firstVisualPixelChangeVerified":false,"under30msAccepted":false,
            "energyVerified":false,"normalGUIDrawPerformanceVerified":false]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("own-window-bounded-events-and-frames.json"))
            try JSONSerialization.data(withJSONObject:IntegrationMotionReplay.audit(rows,truncated:dropped>0),options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("dynamic-motion-replay.json"))
            try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("own-window-timing-summary.json"))
        } catch {fputs("Diagnostic write failed: \(error)\n",stderr)}
    }
}

final class EyeMetalView:MTKView {
    override var isOpaque:Bool{false}
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{nil} // Existing EventCatcher remains the sole input surface.
}

final class IntegratedGPUEyes:NSObject,MTKViewDelegate {
    let backend:MetalBackend
    let view:EyeMetalView
    private(set) var log:LocalStudyLog?
    let defaultTarget:Point2D
    private var motion:SharedGazeMotion
    private var latest:SignalContext?
    private var nextSignal=0,frame=0
    private var dirty=true,inFlight=false
    var onReady:(()->Void)?
    private var ready=false,started=false
    private var nextInput:(kind:String,raw:Double)?
    private var coalesced=false // A only in this version; no B trials.
    private var idle=GazeIdle()
    private var wakeItem:DispatchWorkItem?
    private var armedDeadline:Double?
    private var lastPresentedUnits=Point2D(x:0,y:0)
    private var lastPresentedFrame=0
    private var restLoggedDeadline:Double?
    private var observers:[NSObjectProtocol]=[]
    private var realContext=IdleContext()
    private var finiteTrial=false,trialWasInterrupted=false
    private var segmentCaptureCount=0
    private var pendingCapture:Double?
    private var sampledIdleProgress:Double?
    private var capturesThisSegment=0
    private var requestedDrawReason:String?
    private var lastUITarget:Point2D
    private var lastUIReduced=false
    private let runIdleTrial:Bool
    static weak var active:IntegratedGPUEyes?
    static func localEvent(_ kind:String,event:NSEvent,point:CGPoint?=nil,size:CGSize?=nil,details:[String:Any]=[:]){
        guard let active else{return}
        let now=CACurrentMediaTime();active.nextInput=(kind,event.timestamp)
        var row:[String:Any]=["type":"own-view-event","kind":kind,"receivedHost":now,"rawNSEventTimestamp":event.timestamp]
        if let point,let size {row["localWindowPoint"]=[Double(point.x),Double(point.y)];row["viewSize"]=[Double(size.width),Double(size.height)]}
        row.merge(details){_,new in new};active.log?.add(row)
    }
    static func noteInput(_ kind:String,event:NSEvent){active?.nextInput=(kind,event.timestamp)}
    static func localKey(){active?.keyboardActivity()}
    static func localFocus(_ focused:Bool){active?.focusChanged(focused)}
    func retarget(_ point:Point2D,reduced:Bool){
        let previousUI=lastUITarget;lastUITarget=point
        let input=nextInput;nextInput=nil
        let now=CACurrentMediaTime()
        if reduced != lastUIReduced {
            lastUIReduced=reduced;realContext.reduced=reduced
            interruptTrial("actual-reduce-motion-change")
            holdPresented(now:now);idle.configure(realContext,now:now)
            setGoal(SafeGaze.heading(target:point),kind:.preset,raw:nil,reason:"reduce-motion-policy",reduced:reduced);armWake();return
        }
        guard let input else {
            if point != previousUI {setGoal(SafeGaze.heading(target:point),kind:.preset,raw:nil,reason:"UI-goal-change",reduced:reduced)}
            return
        }
        let exiting=input.kind.hasPrefix("exit")
        if exiting && !realContext.inside {log?.add(["type":"repeat-outside-delivery-no-new-window-exit","host":now]);return}
        interruptTrial("actual-own-window-"+input.kind)
        if idle.engaged {holdPresented(now:now)}
        realContext.inside = !exiting
        idle.configure(realContext,now:now,awaitReturn:exiting && !reduced)
        setGoal(SafeGaze.heading(target:point),kind:exiting ? .localExit:.localPointer,raw:input.raw,reason:"actual-own-window-"+input.kind,reduced:reduced)
        armWake()
    }
    func snapshotSourceChanged(_ point:Point2D,reduced:Bool){
        let now=CACurrentMediaTime();interruptTrial("snapshot-source-changed")
        holdPresented(now:now);lastUITarget=point
        idle.configure(realContext,now:now,awaitReturn:!realContext.inside && !reduced)
        setGoal(SafeGaze.heading(target:point),kind:.preset,raw:nil,reason:"explicit-folder-source-updated",reduced:reduced);armWake()
    }
    init(backend:MetalBackend,diagnostics:URL?,runIdleTrial:Bool=false,startingTarget:Point2D?=nil)throws {
        self.runIdleTrial=runIdleTrial
        let initialTarget=try startingTarget ?? StudyPose.defaultTarget()
        self.backend=backend;defaultTarget=initialTarget;lastUITarget=initialTarget
        motion=SharedGazeMotion(target:SafeGaze.heading(target:initialTarget),time:CACurrentMediaTime(),reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        lastPresentedUnits=SafeGaze.heading(target:initialTarget)
        log=diagnostics.map{LocalStudyLog(directory:$0)}
        view=EyeMetalView(frame:NSRect(x:0,y:0,width:1200,height:900),device:backend.device)
        super.init()
        lastUIReduced=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        realContext.reduced=lastUIReduced
        idle=GazeIdle(seed:runIdleTrial ? 0x46534d6f6e69746f:UInt64.random(in:1...UInt64.max))
        view.delegate=self;view.colorPixelFormat = .bgra8Unorm
        view.clearColor=MTLClearColorMake(0,0,0,0);view.framebufferOnly=true
        view.colorspace=CGColorSpaceCreateDeviceRGB();view.wantsLayer=true
        view.layer?.isOpaque=false
        view.preferredFramesPerSecond=60 // Request ONLY, not measured fps.
        view.enableSetNeedsDisplay=false;view.isPaused=true
        log?.add(["type":"configuration","host":CACurrentMediaTime(),"shaderSHA256":backend.shaderSHA256,
            "pipelineAndTextureInitializationMs":backend.initializationMs,"initializationStageHostMs":backend.initializationStages,"preferredFPSRequest":60,
            "textureSizes":[[638,726],[692,700]],"isOpaque":false,"alpha":"premultiplied, one/oneMinusSourceAlpha",
            "geometry":"2400x1800 unchanged; row0=minY; target/pose now safe conjugate heading units, scale1400/radian; legacy reference retained",
            "firstVisualPixelChangeVerified":false,"physicalInputToPhotonVerified":false])
    }
    func start(){
        guard !started else{return};started=true;Self.active=self
        guard let cb=backend.queue.makeCommandBuffer() else{return}
        inFlight=true
        do{try backend.encodePair(cb,heading:motion.position)}catch{fputs("Initial GPU pair failed: \(error)\n",stderr);return}
        cb.addCompletedHandler{[weak self] c in
            let failed=c.status != .completed
            DispatchQueue.main.async {
                guard let self else{return};self.inFlight=false
                guard !failed else{fputs("Initial GPU pair failed; no CPU fallback\n",stderr);return}
                self.ready=true;self.onReady?();self.onReady=nil;self.requestDraw()
                let now=CACurrentMediaTime();self.idle.configure(self.realContext,now:now);self.armWake()
                if self.log != nil {
                    if self.runIdleTrial {self.startFiniteIdleTrial()}
                    else {DispatchQueue.main.asyncAfter(deadline:.now()+35){[weak self] in self?.log?.finish();self?.log=nil}}
                }
            }
        };cb.commit()
    }
    private func setGoal(_ target:Point2D,kind:SignalKind,raw:Double?,reason:String,received:Double?=nil,reduced:Bool?=nil) {
        let now=received ?? CACurrentMediaTime();nextSignal+=1
        latest=SignalContext(id:nextSignal,kind:kind,receivedHost:now,rawEventTimestamp:raw,goal:target,previous:motion)
        motion.retarget(target,at:now,reduced:reduced ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        dirty=true
        log?.add(["type":"goal","id":nextSignal,"kind":kind.rawValue,"receivedHost":now,"rawNSEventTimestamp":raw.map{$0 as Any} ?? NSNull(),
            "target":[target.x,target.y],"reason":reason,"reducedMotion":motion.reduced,"pairInFlight":inFlight])
        requestDraw()
    }
    // Only this App's lifecycle and existing input surface. No global monitor.
    func observeLifecycle(window:NSWindow){
        realContext.focused=window.isKeyWindow
        func watch(_ name:Notification.Name,_ object:AnyObject,_ action:@escaping()->Void){
            observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main){_ in action()})
        }
        watch(NSWindow.didMiniaturizeNotification,window){[weak self] in self?.visibilityChanged(false)}
        watch(NSWindow.didDeminiaturizeNotification,window){[weak self,weak window] in self?.visibilityChanged(!(window?.isMiniaturized ?? true) && !NSApp.isHidden)}
        watch(NSApplication.didHideNotification,NSApp){[weak self] in self?.visibilityChanged(false)}
        watch(NSApplication.didUnhideNotification,NSApp){[weak self,weak window] in self?.visibilityChanged(!(window?.isMiniaturized ?? true))}
    }
    private func holdPresented(now:Double){
        let p=lastPresentedUnits;motion=SharedGazeMotion(target:p,time:now,reduced:lastUIReduced)
        log?.add(["type":"motion-reset","host":now,"point":[p.x,p.y],"reason":"handoff-from-last-positive-presented-pose"])
    }
    private func keyboardActivity(){
        let now=CACurrentMediaTime();interruptTrial("actual-keyboard")
        if idle.engaged {holdPresented(now:now)}
        idle.configure(realContext,now:now,awaitReturn:!realContext.inside && !motion.settled && !lastUIReduced)
        setGoal(SafeGaze.heading(target:lastUITarget),kind:.preset,raw:nil,reason:"actual-keyboard-cancels-idle-does-not-create-pointer",reduced:lastUIReduced);armWake()
    }
    private func focusChanged(_ focused:Bool){
        guard realContext.focused != focused else{return}
        let now=CACurrentMediaTime();realContext.focused=focused;interruptTrial("actual-focus-change")
        if idle.engaged {holdPresented(now:now)}
        idle.configure(realContext,now:now,awaitReturn:idle.awaitingReturn)
        log?.add(["type":"actual-focus","host":now,"focused":focused]);armWake()
    }
    private func visibilityChanged(_ visible:Bool){
        guard realContext.visible != visible else{return}
        let now=CACurrentMediaTime();realContext.visible=visible;interruptTrial("actual-visibility-change");holdPresented(now:now)
        idle.configure(realContext,now:now,awaitReturn:!realContext.inside && visible && !lastUIReduced)
        log?.add(["type":"actual-visibility","host":now,"visible":visible])
        if visible {setGoal(SafeGaze.heading(target:lastUITarget),kind:.preset,raw:nil,reason:"restore-no-idle-replay",reduced:lastUIReduced)}else{view.isPaused=true}
        armWake()
    }
    private func armWake(){
        let deadline=idle.deadline
        guard deadline != armedDeadline else{return}
        wakeItem?.cancel();wakeItem=nil;armedDeadline=deadline;restLoggedDeadline=nil
        guard let deadline else{return}
        let token=idle.generation
        let item=DispatchWorkItem{[weak self] in
            guard let self else{return};let now=CACurrentMediaTime()
            guard token==self.idle.generation,self.idle.deadline==deadline else{self.log?.add(["type":"stale-idle-callback-rejected","host":now,"token":token]);return}
            self.armedDeadline=nil
            guard self.idle.wake(token:token,expectedDeadline:deadline,now:now,current:self.lastPresentedUnits,settled:self.motion.settled)else{
                self.log?.add(["type":"idle-wake-rejected","host":now,"token":token,"currentGeneration":self.idle.generation]);if self.motion.settled {self.armWake()};return
            }
            let segment=self.idle.segment!;self.capturesThisSegment=0
            self.log?.add(["type":"idle-segment-begin","host":now,"generation":token,"from":[segment.from.x,segment.from.y],"to":[segment.to.x,segment.to.y],"anchor":[self.idle.anchor!.x,self.idle.anchor!.y],"start":segment.start,"duration":segment.duration,"focused":self.idle.context.focused,"inside":self.idle.context.inside,"source":self.finiteTrial ? "synthetic-local-policy-trial-NOT-OS":"actual-App-idle-policy"])
            self.dirty=true;self.requestDraw(reason:"idle-one-shot-wake")
        }
        wakeItem=item;DispatchQueue.main.asyncAfter(deadline:.now()+max(0,deadline-CACurrentMediaTime()),execute:item)
        log?.add(["type":"idle-wake-armed","host":CACurrentMediaTime(),"deadline":deadline,"generation":token,"active":idle.context.active])
    }
    private func markRest(){
        guard motion.settled,idle.segment==nil,let deadline=idle.deadline,deadline != restLoggedDeadline else{return}
        restLoggedDeadline=deadline
        log?.add(["type":"rest-start","host":CACurrentMediaTime(),"deadline":deadline,"generation":idle.generation])
    }
    private func interruptTrial(_ reason:String){
        let beforeStartRealInput=runIdleTrial && (reason.hasPrefix("actual-own-window-") || reason=="actual-keyboard" || (reason=="actual-focus-change" && !realContext.focused) || (reason=="actual-visibility-change" && !realContext.visible))
        guard finiteTrial || beforeStartRealInput else{return};finiteTrial=false;trialWasInterrupted=true
        log?.add(["type":"synthetic-trial-interrupted-by-real-input-or-context","host":CACurrentMediaTime(),"reason":reason])
    }
    private func startFiniteIdleTrial(){
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[weak self] in
            guard let self,!self.trialWasInterrupted else{return};self.finiteTrial=true
            self.syntheticPolicyGoal(SafeGaze.center,inside:true,reason:"trial-center-input")
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+8.5){[weak self] in
            guard let self,self.finiteTrial else{return}
            self.syntheticPolicyGoal(Point2D(x:2350,y:800),inside:true,reason:"trial-input-cancels-wait")
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+16){[weak self] in
            guard let self,self.finiteTrial else{return}
            self.syntheticPolicyGoal(self.defaultTarget,inside:false,reason:"trial-exit-return-then-quiet-wait")
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+32){[weak self] in
            guard let self else{return};let now=CACurrentMediaTime()
            if self.finiteTrial {self.finiteTrial=false;self.holdPresented(now:now);self.idle.configure(self.realContext,now:now,awaitReturn:!self.realContext.inside && !self.lastUIReduced);self.setGoal(SafeGaze.heading(target:self.lastUITarget),kind:.preset,raw:nil,reason:"finite-trial-end-restore-latest-real-UI",reduced:self.lastUIReduced);self.armWake()}
            self.log?.add(["type":"finite-trial-end","host":now,"interruptedByActualInput":self.trialWasInterrupted])
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+34){[weak self] in self?.log?.add(["type":"capture-cutoff","host":CACurrentMediaTime()]);self?.log?.finish();self?.log=nil}
    }
    private func syntheticPolicyGoal(_ target:Point2D,inside:Bool,reason:String){
        let now=CACurrentMediaTime();if idle.engaged {holdPresented(now:now)}
        let context=IdleContext(visible:true,focused:true,inside:inside,reduced:lastUIReduced)
        idle.configure(context,now:now,awaitReturn:!inside && !lastUIReduced)
        setGoal(SafeGaze.heading(target:target),kind:.synthetic,raw:nil,reason:reason+"-NOT-OS",reduced:lastUIReduced);armWake()
    }
    private func requestDraw(reason:String="input",forceTick:Bool=false) {
        precondition(Thread.isMainThread)
        view.isPaused=false
        if !coalesced || forceTick {
            if !inFlight {requestedDrawReason=reason;view.draw()}
            else {log?.add(["type":"draw-skip","reason":reason,"skip":"request-in-flight","host":CACurrentMediaTime()])}
        }
        else {log?.add(["type":"draw-request-coalesced","host":CACurrentMediaTime(),"reason":reason,"inFlight":inFlight])}
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {
        if !Thread.isMainThread {DispatchQueue.main.async{[weak self] in self?.dirty=true;self?.requestDraw(reason:"resize-forward")};return}
        log?.add(["type":"resize","host":CACurrentMediaTime(),"drawableSize":[Double(size.width),Double(size.height)],"viewSize":[Double(view.bounds.width),Double(view.bounds.height)]])
        dirty=true;requestDraw(reason:"resize")
    }
    func draw(in view:MTKView) {
        if !Thread.isMainThread {
            let receipt=CACurrentMediaTime()
            DispatchQueue.main.async{[weak self] in
                self?.log?.add(["type":"tick-main-forward","receivedHost":receipt,"handledHost":CACurrentMediaTime()])
                self?.requestDraw(reason:"mtk-tick-forward",forceTick:true)
            };return
        }
        let reason=requestedDrawReason ?? "mtk-tick-main";requestedDrawReason=nil
        drawFrame(reason:reason)
    }
    private func drawFrame(reason:String){
        precondition(Thread.isMainThread)
        guard ready,realContext.visible,!inFlight else{log?.add(["type":"draw-skip","reason":reason,"skip":ready ? "in-flight":"not-ready","host":CACurrentMediaTime()]);return}
        guard dirty || !motion.settled || idle.segment != nil else{view.isPaused=true;markRest();log?.add(["type":"draw-skip","reason":reason,"skip":"settled-clean","host":CACurrentMediaTime()]);return}
        let phase=log?.phase ?? "off",mode=coalesced ? "B":"A"
        if frame==0,let layer=view.layer as? CAMetalLayer {
            log?.add(["type":"actual-layer-readonly","host":CACurrentMediaTime(),"displaySyncEnabled":layer.displaySyncEnabled,"maximumDrawableCount":layer.maximumDrawableCount,"presentsWithTransaction":layer.presentsWithTransaction,"isOpaque":layer.isOpaque,"drawableSize":[Double(layer.drawableSize.width),Double(layer.drawableSize.height)],"pixelFormat":layer.pixelFormat.rawValue])
        }
        let encodeStart=CACurrentMediaTime()
        let wasIdle=idle.segment
        var shown:Point2D
        if let sample=idle.sample(now:encodeStart) {
            shown=sample.point;sampledIdleProgress=wasIdle.map{min(1,max(0,(encodeStart-$0.start)/$0.duration))}
            if sample.ended {
                motion=SharedGazeMotion(target:shown,time:encodeStart,reduced:lastUIReduced)
                log?.add(["type":"motion-reset","host":encodeStart,"point":[shown.x,shown.y],"reason":"idle-end-hold"])
                log?.add(["type":"idle-segment-end","host":encodeStart]);armWake()
            }
        }else{motion.advance(to:encodeStart);shown=motion.position;sampledIdleProgress=nil}
        if idle.awaitingReturn && motion.settled && idle.segment==nil {idle.returnFinished(now:encodeStart);armWake();log?.add(["type":"default-return-settled","host":encodeStart])}
        let goal=idle.segment?.to ?? motion.target,signal=latest,settled=motion.settled && idle.segment==nil
        if wasIdle != nil,log != nil,segmentCaptureCount<15,let progress=sampledIdleProgress, progress>=Double(capturesThisSegment)/4 {
            pendingCapture=progress;capturesThisSegment+=1;segmentCaptureCount+=1
        }
        guard let cb=backend.queue.makeCommandBuffer() else{return}
        do{try backend.encodePair(cb,heading:shown)}catch{view.isPaused=true;log?.add(["type":"error","message":String(describing:error)]);return}
        let drawableStart=CACurrentMediaTime()
        guard let drawable=view.currentDrawable,let pass=view.currentRenderPassDescriptor,
              let encoder=cb.makeRenderCommandEncoder(descriptor:pass) else {
            log?.add(["type":"drawable-unavailable","host":CACurrentMediaTime()]);return
        }
        let drawableEnd=CACurrentMediaTime()
        backend.encodePresentation(encoder,viewSize:view.bounds.size);encoder.endEncoding()
        let before=CACurrentMediaTime();frame+=1;let frameID=frame
        let distance=hypot(shown.x-goal.x,shown.y-goal.y)
        let influence=wasIdle==nil ? (signal?.influenceDistance(at:encodeStart,shown:shown) ?? 0):0
        let captureProgress=pendingCapture;pendingCapture=nil
        let idleFrame=wasIdle != nil
        inFlight=true;dirty=false
        cb.addCompletedHandler{[weak self] completed in
            let callback=CACurrentMediaTime()
            let gs=completed.gpuStartTime,ge=completed.gpuEndTime,ks=completed.kernelStartTime,ke=completed.kernelEndTime
            let status=completed.status.rawValue,error=completed.error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else{return}
                if let captureProgress,let folder=self.log?.directory {
                    let images=self.backend.readImages()
                    let out=folder.appendingPathComponent("live-idle-Metal-readback-NOT-SCREENSHOT",isDirectory:true)
                    do{try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true);try writePNG(pairComposite(images),to:out.appendingPathComponent("frame-\(frameID)-native-pair.png"));self.log?.add(["type":"live-idle-png","frame":frameID,"progress":captureProgress,"headingUnits":[shown.x,shown.y],"readbackOutsideGPUTime":true,"normalGUIDrawPerformanceVerified":false])}catch{fputs("Idle PNG error: \(error)\n",stderr)}
                }
                self.inFlight=false
                let sane=StudyMetrics.hostTimesPlausible(encode:encodeStart,gpuStart:gs,gpuEnd:ge,callback:callback)
                self.log?.add(["type":"gpu-completed","phase":phase,"mode":mode,"frame":frameID,"callbackHost":callback,"mainHandledHost":CACurrentMediaTime(),"mainQueueWaitMs":(CACurrentMediaTime()-callback)*1000,
                    "gpuStartHost":gs,"gpuEndHost":ge,"driverKernelStartHost":ks,"driverKernelEndHost":ke,
                    "gpuMs":gs>0 && ge>=gs ? ((ge-gs)*1000) as Any:NSNull(),
                    "commitToGPUStartSanityOnlyMs":sane && gs>=before ? ((gs-before)*1000) as Any:NSNull(),
                    "hostOrderingSanityOnlyNotClockCalibration":sane,"status":status,"error":error.map{$0 as Any} ?? NSNull()])
                if error != nil {self.view.isPaused=true;return}
                self.view.isPaused = !self.realContext.visible || (!self.dirty && self.motion.settled && self.idle.segment==nil)
                if self.view.isPaused {self.markRest()}
            }
        }
        do {
            drawable.addPresentedHandler{[weak self] d in
                let callback=CACurrentMediaTime(),presented=d.presentedTime
                DispatchQueue.main.async {
                    guard let self else{return}
                    if presented>0 && frameID>self.lastPresentedFrame {self.lastPresentedFrame=frameID;self.lastPresentedUnits=shown}
                    let plausible=StudyMetrics.presentedPlausible(encode:encodeStart,presented:presented,callback:callback)
                    var row:[String:Any] = ["type":"presented","phase":phase,"mode":mode,"frame":frameID,"presentedHost":presented,"callbackHost":callback,
                        "hostOrderingSanityOnlyNotClockCalibration":plausible,"newGoalInfluenceHeadingUnits":influence,
                        "shownTarget":[shown.x,shown.y],"goal":[goal.x,goal.y],"sampledPoseHost":encodeStart,
                        "distanceToGoalHeadingUnits":distance,"motionSettledAtEncode":settled]
                    if let signal,!idleFrame {
                        row["signalID"]=signal.id;row["signalKind"]=signal.kind.rawValue
                        row["signalReceiptHost"]=signal.receivedHost
                        row["rawNSEventTimestamp"]=signal.rawEventTimestamp.map{$0 as Any} ?? NSNull()
                        if plausible && presented>=signal.receivedHost {
                            row["receiptToPresentedTrajectoryProxyMs"]=(presented-signal.receivedHost)*1000
                            if settled {row["goalSettlePresentedProxyMs"]=(presented-signal.receivedHost)*1000}
                        }
                    }
                    self.log?.add(row)
                }
            }
        }
        cb.present(drawable);cb.commit();let after=CACurrentMediaTime()
        log?.add(["type":"submitted","phase":phase,"mode":mode,"drawReason":reason,"goalAgeAtSampleMs":signal.map{(encodeStart-$0.receivedHost)*1000 as Any} ?? NSNull(),"frame":frameID,"encodeStartHost":encodeStart,"commitBeforeHost":before,"commitAfterHost":after,
            "cpuEncodeMs":max(0,(before-encodeStart-(drawableEnd-drawableStart))*1000),"drawableWaitMs":(drawableEnd-drawableStart)*1000,
            "commitCallMs":(after-before)*1000,"signalID":idleFrame ? NSNull():signal.map{$0.id as Any} ?? NSNull(),"distanceToGoalHeadingUnits":distance,
            "shownTarget":[shown.x,shown.y],"goal":[goal.x,goal.y],"samePairTarget":true,"motionSettled":settled,"idleFrame":idleFrame,"headingUnitScale":SafeGaze.unitsPerRadian])
        view.isPaused = !realContext.visible || settled // Completion only releases one pair; never blocks main thread.
    }
}

#endif
