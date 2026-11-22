#if os(macOS)
import AppKit
import SwiftUI
import CryptoKit
import DemoFirstScreenCore
import EyeStudySupport

/// Explicit app-internal composite: actual SwiftUI cacheDisplay without eyes,
/// actual Metal texture readback, and actual foreground SwiftUI cacheDisplay.
/// NOT a screenshot, not cacheDisplay magically including CAMetalLayer.
enum GPUIntegrationEvidence {
    static func render(_ session:InteractionSession,part:DemoRenderPart)throws->PixelImage {
        let root=DemoRootView(snapshot:session.snapshot,session:session,renderPart:part)
            .frame(width:1200,height:900).background(Color.clear)
        let host=ClearHostingView(rootView:root)
        host.wantsLayer=true;host.layer?.isOpaque=false;host.layer?.backgroundColor=NSColor.clear.cgColor
        host.frame=NSRect(x:0,y:0,width:1200,height:900);host.appearance=NSAppearance(named:.aqua)
        host.layoutSubtreeIfNeeded()
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2400,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:9600,bitsPerPixel:32),let ptr=rep.bitmapData else{throw StudyFailure("Full SwiftUI bitmap allocation")}
        rep.size=NSSize(width:1200,height:900);memset(ptr,0,rep.bytesPerRow*rep.pixelsHigh)
        host.cacheDisplay(in:host.bounds,to:rep)
        guard !rep.bitmapFormat.contains(.alphaFirst),!rep.bitmapFormat.contains(.alphaNonpremultiplied),rep.bytesPerRow==9600 else{throw StudyFailure("Unexpected SwiftUI RGBA/premultiplication format")}
        return PixelImage(minX:0,minY:0,width:2400,height:1800,rgba:Array(UnsafeBufferPointer(start:ptr,count:9600*1800)))
    }
    static func fullPNG(_ p:PixelImage,to url:URL)throws {
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:p.width,pixelsHigh:p.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:p.width*4,bitsPerPixel:32),let dst=rep.bitmapData else{throw StudyFailure("Full PNG buffer")}
        rep.size=NSSize(width:1200,height:900)
        p.rgba.withUnsafeBytes{memcpy(dst,$0.baseAddress!,p.rgba.count)}
        guard let data=rep.representation(using:.png,properties:[:])else{throw StudyFailure("Full PNG encoding")}
        try data.write(to:url)
    }
    static func over(_ src:PixelImage,_ dst:inout PixelImage) {
        for y in 0..<src.height {for x in 0..<src.width {
            let tx=Int(src.minX)+x,ty=Int(src.minY)+y
            guard tx>=0,ty>=0,tx<dst.width,ty<dst.height else{continue}
            let s=(y*src.width+x)*4,d=(ty*dst.width+tx)*4,a=Int(src.rgba[s+3]);if a==0{continue}
            for c in 0..<4 {dst.rgba[d+c]=UInt8(min(255,Int(src.rgba[s+c])+(Int(dst.rgba[d+c])*(255-a)+127)/255))}
        }}
    }
    static func byteDifference(_ a:PixelImage,_ b:PixelImage)->[String:Any]{
        var bytes=0,pixels=0,maximum=0
        for i in stride(from:0,to:a.rgba.count,by:4){var changed=false
            for c in 0..<4 {let d=abs(Int(a.rgba[i+c])-Int(b.rgba[i+c]));if d>0{bytes+=1;changed=true};maximum=max(maximum,d)}
            if changed{pixels+=1}
        }
        return ["differentBytes":bytes,"differentPixels":pixels,"maxPremultRGBA8Delta":maximum]
    }
    static func write(example:DemoSnapshot,backend:MetalBackend,to folder:URL)throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var overview=InteractionSession(snapshot:example)
        let hover=overview.layout.pointOnRay(degrees:200,radiusFraction:0.55)
        var h=overview;h.pointerMoved(to:hover)
        var lock=h;lock.pointerClicked(at:hover)
        var projects=overview;projects.pointerMoved(to:try StudyPose.projects.target())
        var join=overview;join.pointerMoved(to:try StudyPose.joinMidpoint.target())
        let cases:[(String,InteractionSession)]=[("overview",overview),("hover-movies",h),("locked-movies",lock),("projects",projects),("join-midpoint",join)]
        var reports:[[String:Any]]=[]
        for (name,session) in cases {
            let frame=FramePresentation.make(session:session,motion:.reduced,pointerInsideWindow:session.state.pointerLocation != nil)
            let gpu=try backend.verifyPair(target:frame.eye.resolvedTarget).images
            // Entire current full UI without eyes, including cards above the eye layer.
            let base=try render(session,part:.withoutEyes),fg=try render(session,part:.foregroundOnly)
            let cpu=try render(session,part:.normal)
            var eyeAlpha=[UInt8](repeating:0,count:2400*1800),eyeQuad=[Bool](repeating:false,count:2400*1800),foregroundOverlap=0
            for image in gpu {for y in 0..<image.height {for x in 0..<image.width {
                let at=(Int(image.minY)+y)*2400+Int(image.minX)+x
                let a=image.rgba[(y*image.width+x)*4+3];eyeAlpha[at]=max(eyeAlpha[at],a);eyeQuad[at]=true
            }}}
            for pixel in eyeAlpha.indices where eyeAlpha[pixel]>0 && fg.rgba[pixel*4+3]>0 {foregroundOverlap+=1}
            // Current five evidence cases have no card/eye overlap. Fail rather than
            // silently putting GPU eyes over foreground text in the composite.
            guard foregroundOverlap==0 else{throw StudyFailure("Foreground intersects eyes in \(name): requires explicit underlay+foreground split, not wrong-order evidence")}
            var full=base;for eye in gpu{over(eye,&full)}
            var split:[String:Any]=[:]

            var outsideDifferentBytes=0,maxOutsideDelta=0,transparentQuadDifference=0,maxTransparentQuadDelta=0,eyeCompositeMaxDelta=0
            for pixel in eyeAlpha.indices {for c in 0..<4 {
                let i=pixel*4+c,d=abs(Int(full.rgba[i])-Int(cpu.rgba[i]))
                if !eyeQuad[pixel],d>0 {outsideDifferentBytes+=1;maxOutsideDelta=max(maxOutsideDelta,d)}
                if eyeQuad[pixel]{eyeCompositeMaxDelta=max(eyeCompositeMaxDelta,d)}
                if eyeQuad[pixel] && eyeAlpha[pixel]==0 && d>0 {transparentQuadDifference+=1;maxTransparentQuadDelta=max(maxTransparentQuadDelta,d)}
            }}
            try fullPNG(full,to:folder.appendingPathComponent("integrated-\(name)-GPU-plus-SwiftUI-OFFSCREEN-COMPOSITE-NOT-SCREENSHOT.png"))
            try fullPNG(cpu,to:folder.appendingPathComponent("reference-\(name)-CPU-OFFSCREEN-NOT-SCREENSHOT.png"))
            if name=="overview" {
                try fullPNG(base,to:folder.appendingPathComponent("overview-actual-SwiftUI-without-eyes.png"))
                try fullPNG(fg,to:folder.appendingPathComponent("overview-actual-SwiftUI-foreground.png"))
            }
            reports.append(["nativeCPUCompositionDiagnostic":split,"case":name,"target":[frame.eye.resolvedTarget.x,frame.eye.resolvedTarget.y],"foregroundEyeOverlapPixels":foregroundOverlap,
                "nonEyeDifferentRGBABytesVsSame163929CPUUI":outsideDifferentBytes,"nonEyeMaxDelta":maxOutsideDelta,
                "nonEyeRegionDefinition":"Outside BOTH complete GPU texture quads (not zero-alpha texels inside quads)",
                "insideEyeQuadButGPUAlphaZeroDifferentBytesVsCPUCanvas":transparentQuadDifference,
                "insideEyeQuadButGPUAlphaZeroMaxPremultDelta":maxTransparentQuadDelta,
                "eyeQuadCompositeMaxPremultDeltaVsCPUCanvas":eyeCompositeMaxDelta,
                "visibleSmallCardIDs":frame.visibleSectorCoreLabels.map(\.id),"expandedName":frame.info.name,
                "expandedVisible":frame.infoPlacement.isVisible && !frame.info.isOverview,
                "leftRawGPU_SHA256":SHA256.hash(data:Data(gpu[0].rgba)).map{String(format:"%02x",$0)}.joined(),
                "rightRawGPU_SHA256":SHA256.hash(data:Data(gpu[1].rgba)).map{String(format:"%02x",$0)}.joined()])
        }
        let report:[String:Any]=["note":"Actual unchanged SwiftUI full UI cacheDisplay WITHOUT legacy CPU eyes, then same-backend Metal texture readback. Foreground overlap measured zero in all selected cases. GPU eyes are NOT cacheDisplay fallback. NOT OS screenshot or real GUI composition proof.",
            "canvas":[2400,1800],"readbackOutsidePerformanceMeasurement":true,"cases":reports,"qualityAccepted":false,"GUICompositionVerified":false,
            "presentationDifferenceNotAccepted":"Authorized safe target-to-heading mapping differs intentionally from legacy near-convergence CPU Canvas. Shader equality is tested separately at identical frozen legacy direction/uniform inputs. GUI color/composition still unverified.","physicalInputToPhotonVerified":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("integrated-full-evidence-report.json"))
    }
}
#endif
