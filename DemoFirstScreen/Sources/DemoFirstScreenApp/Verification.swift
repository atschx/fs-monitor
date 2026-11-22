#if os(macOS)
import AppKit
import CryptoKit
import DemoFirstScreenCore
import EyeStudySupport

func writePNG(_ p:PixelImage,to url:URL)throws {
    let data=Data(p.rgba) as CFData
    guard let provider=CGDataProvider(data:data),
          let cg=CGImage(width:p.width,height:p.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:p.width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),
          let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else {throw StudyFailure("PNG encoding failed")}
    try png.write(to:url)
}
func pairComposite(_ images:[PixelImage])->PixelImage {
    var p=PixelImage(minX:0,minY:0,width:2400,height:1800,rgba:[UInt8](repeating:0,count:2400*1800*4))
    for image in images {for row in 0..<image.height {for col in 0..<image.width {
        let x=Int(image.minX)+col,y=Int(image.minY)+row
        guard x>=0,y>=0,x<p.width,y<p.height else{continue}
        let s=(row*image.width+col)*4,d=(y*p.width+x)*4,a=Int(image.rgba[s+3])
        for c in 0..<4 {p.rgba[d+c]=UInt8(min(255,Int(image.rgba[s+c])+(Int(p.rgba[d+c])*(255-a)+127)/255))}
    }}}
    return p
}
/// Native-scale cropped contact comparison, CPU left / GPU right; NOT screen capture.
func checkerComparison(cpu:PixelImage,gpu:PixelImage)->PixelImage {
    let x0=549,y0=3,w=1314,h=812
    var image=PixelImage(minX:0,minY:0,width:w*2,height:h,rgba:[UInt8](repeating:255,count:w*2*h*4))
    for (side,pair) in [cpu,gpu].enumerated() {for y in 0..<h {for x in 0..<w {
        let src=((y+y0)*pair.width+x+x0)*4,dst=(y*w*2+side*w+x)*4
        let bg=((x/24+y/24)%2==0) ? 128:224,a=Int(pair.rgba[src+3])
        for c in 0..<3 {image.rgba[dst+c]=UInt8(min(255,Int(pair.rgba[src+c])+(bg*(255-a)+127)/255))}
    }}}
    return image
}
func straight(_ p:PixelImage,_ i:Int)->(Int,Int,Int,Int) {
    let a=Int(p.rgba[i+3]);if a==0{return(0,0,0,0)}
    func c(_ o:Int)->Int {min(255,(Int(p.rgba[i+o])*255+a/2)/a)}
    return(c(0),c(1),c(2),a)
}
func iris(_ p:PixelImage,_ spec:VectorEyeSpec)->[String:Any] {
    let v=SphereImageMeasure.darkIrisCentroid(sclera:spec.sclera) {x,y in
        let col=Int(floor(Double(x)-p.minX)),row=Int(floor(Double(y)-p.minY))
        guard col>=0,row>=0,col<p.width,row<p.height else{return nil}
        let a=straight(p,(row*p.width+col)*4);return(a.0,a.1,a.2,a.3)
    }
    guard let v else{return["measured":false]}
    return["measured":true,"center":[v.canvasX,v.canvasY],"unit":[v.unitX,v.unitY],"samples":v.samples]
}
func highlightMask(_ p:PixelImage,_ spec:VectorEyeSpec,_ target:Point2D)->[Bool] {
    let pose=SafeGaze.pose(spec:spec,heading:SafeGaze.heading(target:target)),e=spec.sclera
    var base=[Bool](repeating:false,count:p.width*p.height)
    for row in 0..<p.height {for col in 0..<p.width {
        let x=(p.minX+Double(col)+0.5-e.center.x)/e.radiusX
        let y=(p.minY+Double(row)+0.5-e.center.y)/e.radiusY
        if let h=SphereShade.wetSurfaceHit(unitX:x,unitY:y,dir:pose.direction,irisAlpha:pose.irisAngularRadius),
           SphereShade.wetReflection(normal:h.normal,cornealWeight:h.cornealWeight)>0.10 {
            base[row*p.width+col]=true
        }
    }}
    var mask=base
    for row in 0..<p.height {for col in 0..<p.width where base[row*p.width+col] {
        for y in max(0,row-2)...min(p.height-1,row+2) {for x in max(0,col-2)...min(p.width-1,col+2){mask[y*p.width+x]=true}}
    }}
    return mask
}
func highlight(_ p:PixelImage,_ mask:[Bool])->[String:Any] {
    var area=0,count=0,peak=0.0,sx=0.0,sy=0.0
    for i in mask.indices where mask[i] {
        let q=straight(p,i*4);guard q.3>=200 else{continue};count+=1
        peak=max(peak,(Double(q.0)+Double(q.1)+Double(q.2))/3)
        if min(q.0,min(q.1,q.2))>=235 {
            area+=1;sx+=p.minX+Double(i%p.width)+0.5;sy+=p.minY+Double(i/p.width)+0.5
        }
    }
    return["referenceMaskSamples":count,"peakMeanRGB255":peak,"neutralWhiteAreaPx":area,
        "neutralWhiteCentroid":area>0 ? [sx/Double(area),sy/Double(area)] as Any : NSNull(),
        "definition":"CPU Double wetReflection>0.10 mask dilated2px; alpha>=200; white=min(R,G,B)>=235. Proxy, not full optical glint segmentation; displacement outside ROI requires image review."]
}
func differences(_ cpu:PixelImage,_ gpu:PixelImage,spec:VectorEyeSpec,target:Point2D)->[String:Any] {
    var hist=[Int](repeating:0,count:256),alphaHist=hist,globeHist=hist,shellHist=hist,maxDelta=0,alphaMax=0,different=0,contour=0,opaque=0,aaDifferent=0
    let e=spec.sclera,edge=1.6/min(e.radiusX,e.radiusY)
    for pixel in 0..<(cpu.width*cpu.height) {
        let off=pixel*4;var changed=false
        let ux=(cpu.minX+Double(pixel%cpu.width)+0.5-e.center.x)/e.radiusX
        let uy=(cpu.minY+Double(pixel/cpu.width)+0.5-e.center.y)/e.radiusY
        let inGlobe=ux*ux+uy*uy<1
        for c in 0..<4 {
            let d=abs(Int(cpu.rgba[off+c])-Int(gpu.rgba[off+c]));hist[d]+=1;maxDelta=max(maxDelta,d);changed = changed || d>0
            if c==3 {alphaHist[d]+=1;alphaMax=max(alphaMax,d)}
            if inGlobe {globeHist[d]+=1}else{shellHist[d]+=1}
        }
        if changed {different+=1}
        if (cpu.rgba[off+3]>0) != (gpu.rgba[off+3]>0){contour+=1}
        if (cpu.rgba[off+3]>=200) != (gpu.rgba[off+3]>=200){opaque+=1}
        if changed {
            let x=(cpu.minX+Double(pixel%cpu.width)+0.5-e.center.x)/e.radiusX
            let y=(cpu.minY+Double(pixel/cpu.width)+0.5-e.center.y)/e.radiusY
            let rho=hypot(x,y);if rho<1 && rho>1-edge {aaDifferent+=1}
        }
    }
    func p95(_ h:[Int])->Int {
        let n=h.reduce(0,+);var sum=0
        for i in 0..<h.count {sum+=h[i];if sum>=Int(ceil(Double(n)*0.95)){return i}}
        return 255
    }
    let mask=highlightMask(cpu,spec,target)
    return["maxPremultRGBA8Delta":maxDelta,"p95PremultRGBA8Delta":p95(hist),"alphaP95Delta":p95(alphaHist),"alphaMaxDelta":alphaMax,"globePremultRGBA8P95":p95(globeHist),"fixedShellAndTransparentPremultRGBA8P95":p95(shellHist),
        "differentPixelCount":different,"pixelCount":cpu.width*cpu.height,"alphaNonzeroContourXOR":contour,"alpha200MaskXOR":opaque,"changedGlobeAAPixels":aaDifferent,
        "cpuIris":iris(cpu,spec),"gpuIris":iris(gpu,spec),"cpuHighlightProxy":highlight(cpu,mask),"gpuHighlightProxy":highlight(gpu,mask),
        "rgbaByteIdentical":cpu.rgba==gpu.rgba,"cpuRGBA_SHA256":SHA256.hash(data:Data(cpu.rgba)).map{String(format:"%02x",$0)}.joined(),
        "gpuRGBA_SHA256":SHA256.hash(data:Data(gpu.rgba)).map{String(format:"%02x",$0)}.joined(),"qualityAccepted":false]
}
func runVerification(_ backend:MetalBackend,to directory:URL)throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    var records:[[String:Any]]=[]
    let first=try backend.verifyPair(target:StudyPose.moviesDefault.target(),readback:false)
    for pose in StudyPose.allCases {
        let target=try pose.target()
        for _ in 0..<2 {_ = try backend.verifyPair(target:target,readback:false)}
        var samples:[[String:Any]]=[]
        for _ in 0..<5 {samples.append(try backend.verifyPair(target:target,readback:false).metrics)}
        // Readback, CPU reference, metrics and PNG are after the timed five runs.
        let capture=try backend.verifyPair(target:target)
        var cpu:[PixelImage]=[],metrics:[[String:Any]]=[]
        for (i,spec) in MetalBackend.specs.enumerated() {
            let ref=BaselineRaster.render(spec:spec,pose:SafeGaze.pose(spec:spec,heading:SafeGaze.heading(target:target)))
            let image=PixelImage(minX:ref.minX,minY:ref.minY,width:ref.width,height:ref.height,rgba:ref.rgba)
            cpu.append(image)
            let side=i==0 ? "left":"right"
            try writePNG(image,to:directory.appendingPathComponent("\(pose.rawValue)-\(side)-CPU-Double.png"))
            try writePNG(capture.images[i],to:directory.appendingPathComponent("\(pose.rawValue)-\(side)-GPU-FP32.png"))
            metrics.append(differences(image,capture.images[i],spec:spec,target:target))
        }
        let cpuPair=pairComposite(cpu),gpuPair=pairComposite(capture.images)
        try writePNG(cpuPair,to:directory.appendingPathComponent("\(pose.rawValue)-pair-CPU-Double-DIAGNOSTIC-COMPOSITE.png"))
        try writePNG(gpuPair,to:directory.appendingPathComponent("\(pose.rawValue)-pair-GPU-FP32-DIAGNOSTIC-COMPOSITE.png"))
        try writePNG(checkerComparison(cpu:cpuPair,gpu:gpuPair),to:directory.appendingPathComponent("\(pose.rawValue)-NATIVE-SCALE-CPU-left-GPU-right-CHECKER.png"))
        let gpu=samples.compactMap{$0["gpuMs"] as? Double},encode=samples.compactMap{$0["encodeMs"] as? Double}
        records.append(["pose":pose.rawValue,"target":[target.x,target.y],"gpuComputePairMs":StudyMetrics.stats(gpu),"cpuEncodeMs":StudyMetrics.stats(encode),"rawStageSamples":samples,"eyesLeftRight":metrics])
    }
    let report:[String:Any] = ["technicalVerificationFinished":true,"qualityAccepted":false,"replacesCPUProduct":false,
        "shaderSHA256":backend.shaderSHA256,"deviceName":backend.device.name,"pipelineAndTexturesInitializationMs":backend.initializationMs,"initializationStageHostMs":backend.initializationStages,
        "coldFirstCompute":first.metrics,"cases":records,"texturePixels":[[638,726],[692,700]],
        "encoding":"RGBA8Unorm offscreen, BGRA8Unorm screen; DeviceRGB tags, no sRGB encoding, premultiplied; screen color management not yet validated",
        "precisionRisk":"MSL Float vs frozen CPU Double; 1e-9/18-bisection unchanged. Differences assessed only, not approved. No hidden CPU fallback for GPU evidence.",
        "evidenceBoundary":"PNG is GPU texture readback after completion, and labeled pixel composites. NOT NSView screenshot, actual window composition, real OS input or physical input-to-photon.",
        "performanceBoundary":"Five warmed compute-only samples per pose, no readback/hash/PNG in timed command region. Offline synchronous waits ONLY here, not live renderer. Not end-to-end <30ms evidence."]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("gpu-cpu-verification.json"))
}
#endif
