#if os(macOS)
import AppKit
import SwiftUI
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

enum StartupSummaryEvidence {
    static func render(store:StartupSummaryStore,session:InteractionSession?,part:DemoRenderPart)throws->PixelImage {
        let driver=EyeFrameDriver(target:SafeGaze.center,frozen:true,source:.inAppEvidence)
        let root=StartupSummaryRootView(store:store,eyes:driver,renderPart:part,evidenceSession:session).frame(width:1200,height:900).background(Color.clear)
        let host=ClearHostingView(rootView:root);host.wantsLayer=true;host.layer?.isOpaque=false;host.layer?.backgroundColor=NSColor.clear.cgColor
        host.frame=NSRect(x:0,y:0,width:1200,height:900);host.appearance=NSAppearance(named:.aqua);host.layoutSubtreeIfNeeded()
        guard store.scansStarted==0 else{throw StudyFailure("Rendering must not initiate startup traversal")}
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2400,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:9600,bitsPerPixel:32),let ptr=rep.bitmapData else{throw StudyFailure("Summary evidence buffer")}
        rep.size=NSSize(width:1200,height:900);memset(ptr,0,rep.bytesPerRow*rep.pixelsHigh);host.cacheDisplay(in:host.bounds,to:rep)
        guard !rep.bitmapFormat.contains(.alphaFirst),!rep.bitmapFormat.contains(.alphaNonpremultiplied)else{throw StudyFailure("Summary evidence premultiplication")}
        return PixelImage(minX:0,minY:0,width:2400,height:1800,rgba:Array(UnsafeBufferPointer(start:ptr,count:9600*1800)))
    }
    static func write(backend:MetalBackend,to out:URL)throws {
        guard !FileManager.default.fileExists(atPath:out.path)else{throw StudyFailure("Do not overwrite summary evidence")}
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let fixture=out.appendingPathComponent("OWN-CREATED-TINY-SECTORS-fixture");try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        for (name,size)in [("目录一：很长的实际名称用于边界测量",3000),("目录二：相邻扇区边界测量",2900),("目录三：很窄很窄的小区",3),("目录四：极小真实区",2),("目录五",1)] {
            let d=fixture.appendingPathComponent(name);try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);try Data(repeating:1,count:size).write(to:d.appendingPathComponent("own-fixture.bin"))
        }
        try Data(repeating:1,count:7).write(to:fixture.appendingPathComponent("root-own-fixture.bin"))
        let scan=DirectoryScanner.scan(root:fixture,cancellation:ScanCancellation()),result=FolderAdapter.adapt(scan)
        guard result.isComplete,result.snapshot.folderLogicalProof?.bucketTotal==5913 else{throw StudyFailure("Summary own-fixture source totals")}
        var complete=FolderReadState();let g=complete.begin(root:result.root);_=complete.finish(result,generation:g,root:result.root)
        var ps=scan;ps.issues=[ScanIssue(path:"fixture",message:"权限缺失注入；非FDA实测")];let partialResult=FolderAdapter.adapt(ps);var partial=FolderReadState();let pg=partial.begin(root:partialResult.root);_=partial.finish(partialResult,generation:pg,root:partialResult.root)
        var reading=FolderReadState();let rg=reading.begin(root:result.root);reading.progress(7,generation:rg,root:result.root)
        let cases:[(String,String,FolderReadState)]=[("first-open","neutral",FolderReadState()),("authorization-INJECTED","authorization",FolderReadState()),("read-so-far-INJECTED","reading",reading),("complete-OWN-FIXTURE","complete",complete),("tiny-sector-expanded-OWN-FIXTURE","complete",complete),("partial-INJECTED","partial",partial),("cancelled-INJECTED","cancelled",FolderReadState())]
        var reports=[[String:Any]]()
        for (name,phase,state) in cases {
            let store=StartupSummaryStore()
            if phase != "neutral" {store.injectEvidence(state:state,phase:phase,message:phase=="authorization" ? "授权引导状态注入：本人在系统设置授予FDA；返回仅尝试一次，不表示授权成功。本证据没有打开设置或扫描启动盘。":"离屏验证：仅自建fixture；容量1TB/可用128GB为注入，非本机启动盘。",candidates:phase=="reading" || phase=="partial" ? result.snapshot.items:[])}
            var session=InteractionSession(snapshot:store.displaySnapshot)
            if name.hasPrefix("tiny-sector-expanded"),let smallest=session.chartability.sectors.min(by:{$0.bytes<$1.bytes}) {
                session.pointerMoved(to:session.layout.visibleInteriorPoint(startDegrees:smallest.startDegrees,endDegrees:smallest.endDegrees))
            }
            let frame=FramePresentation.make(session:session,motion:.reduced,pointerInsideWindow:session.state.pointerLocation != nil)
            var base=try render(store:store,session:session,part:.withoutEyes);let fg=try render(store:store,session:session,part:.foregroundOnly)
            let images=try backend.verifyPair(target:frame.eye.resolvedTarget).images
            var overlap=0
            for image in images{for y in 0..<image.height{for x in 0..<image.width{let at=(Int(image.minY)+y)*2400+Int(image.minX)+x;if image.rgba[(y*image.width+x)*4+3]>0 && fg.rgba[at*4+3]>0{overlap+=1}}}}
            guard overlap==0 else{throw StudyFailure("Summary foreground overlaps GPU eyes")}
            let boxes=DemoRootView(snapshot:store.displaySnapshot,session:session,renderPart:.withoutEyes).measuredRealCards
            let values=Array(boxes.values)
            for i in values.indices{for j in values.indices where j>i {guard !values[i].overlaps(values[j])else{throw StudyFailure("Measured real card collision")}}}
            for image in images{GPUIntegrationEvidence.over(image,&base)}
            try GPUIntegrationEvidence.fullPNG(base,to:out.appendingPathComponent(name+"-GPU-plus-SwiftUI-NOT-SCREENSHOT.png"))
            reports.append(["case":name,"source":name.contains("OWN-FIXTURE") ? "actual reused scanner on own-created fixture":"injected UI state / no startup traversal","scansStarted":store.scansStarted,"phase":phase,"chartable":frame.isChartable,"defaultTargetID":frame.eye.defaultTargetID.map{$0 as Any} ?? NSNull(),"boxes":boxes.map{["id":$0.key,"center":[$0.value.center.x,$0.value.center.y],"size":[$0.value.width,$0.value.height],"leader":$0.value.needsLeader]},"sourceItems":state.snapshot.items.map{["id":$0.id,"name":$0.name,"bytes":$0.knownBytes.map{$0 as Any} ?? NSNull()]}])
        }
        try JSONSerialization.data(withJSONObject:["scope":"No user/startup directory traversal. Own fixtures plus labeled injected permission/capacity states. Actual native Metal readback + SwiftUI underlay, NOT GUI screenshots/FDA proof.","cases":reports],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("summary-fixture-evidence.json"))
    }
}
#endif
