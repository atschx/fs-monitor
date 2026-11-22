#if os(macOS)
import AppKit
import SwiftUI
import CryptoKit
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

enum FolderSnapshotEvidence {
    static func render(_ state:FolderReadState,part:DemoRenderPart)throws->PixelImage {
        let frame=FramePresentation.make(session:InteractionSession(snapshot:state.snapshot),motion:.reduced,pointerInsideWindow:false)
        let driver=EyeFrameDriver(target:frame.eye.resolvedTarget,frozen:true,source:.inAppEvidence)
        let store=FolderSnapshotStore(state:state)
        let root=FolderSnapshotRootView(store:store,eyes:driver,renderPart:part).frame(width:1200,height:900).background(Color.clear)
        let host=ClearHostingView(rootView:root);host.wantsLayer=true;host.layer?.isOpaque=false;host.layer?.backgroundColor=NSColor.clear.cgColor
        host.frame=NSRect(x:0,y:0,width:1200,height:900);host.appearance=NSAppearance(named:.aqua);host.layoutSubtreeIfNeeded()
        guard store.scansStarted==0 else{throw StudyFailure("Rendering/initialization must not trigger a scan")}
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2400,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:9600,bitsPerPixel:32),let ptr=rep.bitmapData else{throw StudyFailure("Folder evidence bitmap")}
        rep.size=NSSize(width:1200,height:900);memset(ptr,0,rep.bytesPerRow*rep.pixelsHigh);host.cacheDisplay(in:host.bounds,to:rep)
        guard !rep.bitmapFormat.contains(.alphaFirst),!rep.bitmapFormat.contains(.alphaNonpremultiplied) else{throw StudyFailure("Folder evidence pixel format")}
        return PixelImage(minX:0,minY:0,width:2400,height:1800,rgba:Array(UnsafeBufferPointer(start:ptr,count:9600*1800)))
    }
    static func write(backend:MetalBackend,to directory:URL)throws {
        guard !FileManager.default.fileExists(atPath:directory.path)else{throw StudyFailure("Do not overwrite folder evidence")}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let fixture=directory.appendingPathComponent("OWN-CREATED-fixture-five-directories-and-file")
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        for (name,size) in [("Alpha",53),("Beta",89),("Gamma",144),("Delta",233),("Epsilon",377)] {
            let child=fixture.appendingPathComponent(name);try FileManager.default.createDirectory(at:child,withIntermediateDirectories:true)
            try Data(repeating:71,count:size).write(to:child.appendingPathComponent("fixture.bin"))
        }
        try Data(repeating:72,count:610).write(to:fixture.appendingPathComponent("root-fixture.bin"))
        let raw=DirectoryScanner.scan(root:fixture,cancellation:ScanCancellation()),result=FolderAdapter.adapt(raw)
        guard result.isComplete,result.snapshot.items.count==5,result.snapshot.items.last?.bytes==663,result.snapshot.folderLogicalProof?.bucketTotal==1506 else{throw StudyFailure("Actual scanner fixture bucket/source mismatch")}
        var complete=FolderReadState();let g=complete.begin(root:result.root);_=complete.finish(result,generation:g,root:result.root)
        var reading=FolderReadState();let rg=reading.begin(root:result.root);reading.progress(3,generation:rg,root:result.root)
        var injected=raw;injected.issues=[ScanIssue(path:"Alpha",message:"权限拒绝注入；不是实际TCC实验")]
        let partialResult=FolderAdapter.adapt(injected);var partial=FolderReadState();let pg=partial.begin(root:partialResult.root);_=partial.finish(partialResult,generation:pg,root:partialResult.root)
        var sameCancel=complete;_=sameCancel.begin(root:result.root);sameCancel.cancel()
        var otherCancel=complete;_=otherCancel.begin(root:directory.appendingPathComponent("NOT-READ-another-range").path);otherCancel.cancel()
        let emptyURL=directory.appendingPathComponent("OWN-CREATED-empty-fixture");try FileManager.default.createDirectory(at:emptyURL,withIntermediateDirectories:true)
        let er=FolderAdapter.adapt(DirectoryScanner.scan(root:emptyURL,cancellation:ScanCancellation()));var empty=FolderReadState();let eg=empty.begin(root:er.root);_=empty.finish(er,generation:eg,root:er.root)
        let cases:[(String,FolderReadState)]=[("first-open-neutral",FolderReadState()),("reading-count-INJECTED",reading),("complete-ACTUAL-OWN-FIXTURE",complete),("partial-permission-INJECTED",partial),("same-range-cancel-stale-INJECTED",sameCancel),("other-range-cancel-neutral-INJECTED",otherCancel),("empty-ACTUAL-OWN-FIXTURE",empty)]
        var reports=[[String:Any]]()
        for (name,state) in cases {
            var base=try render(state,part:.withoutEyes);let fg=try render(state,part:.foregroundOnly)
            let frame=FramePresentation.make(session:InteractionSession(snapshot:state.snapshot),motion:.reduced,pointerInsideWindow:false)
            let images=try backend.verifyPair(target:frame.eye.resolvedTarget).images
            var overlap=0
            for image in images {for y in 0..<image.height {for x in 0..<image.width {let at=(Int(image.minY)+y)*2400+Int(image.minX)+x;if image.rgba[(y*image.width+x)*4+3]>0 && fg.rgba[at*4+3]>0 {overlap+=1}}}}
            guard overlap==0 else{throw StudyFailure("Folder foreground over eye requires explicit split")}
            for image in images {GPUIntegrationEvidence.over(image,&base)}
            try GPUIntegrationEvidence.fullPNG(base,to:directory.appendingPathComponent(name+"-GPU-plus-SwiftUI-NOT-SCREENSHOT.png"))
            reports.append(["case":name,"status":state.status,"stale":state.stale,"snapshotID":state.snapshot.id,"root":state.root.map{$0 as Any} ?? NSNull(),"chartable":frame.isChartable,"items":state.snapshot.items.map{["id":$0.id,"name":$0.name,"knownBytes":$0.knownBytes.map{$0 as Any} ?? NSNull(),"readStatus":$0.readStatus.rawValue]},"sectors":InteractionSession(snapshot:state.snapshot).chartability.sectors.map{["id":$0.id,"bytes":$0.bytes,"start":$0.startDegrees,"end":$0.endDegrees]},"defaultTargetID":frame.eye.defaultTargetID.map{$0 as Any} ?? NSNull(),"defaultTarget":[frame.eye.resolvedTarget.x,frame.eye.resolvedTarget.y],"foregroundEyeOverlapPixels":overlap])
        }
        let report:[String:Any]=["startupStoreScansStarted":FolderSnapshotStore().scansStarted,"scope":"Actual reused scanner only on newly created own fixtures. Permission/reading/cancel states explicitly injected. Same-source GPU native readback + actual SwiftUI underlay, NOT GUI screenshot/TCC/user-directory proof.","APFSPhysicalDedupClaim":false,"cases":reports]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("folder-fixture-source-and-states.json"))
    }
}
#endif
