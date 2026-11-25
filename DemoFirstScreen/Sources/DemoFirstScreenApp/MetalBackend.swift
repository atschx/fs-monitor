#if os(macOS)
import AppKit
import MetalKit
import CryptoKit
import DemoFirstScreenCore
import EyeStudySupport

struct StudyFailure: Error, CustomStringConvertible {
    let description:String
    init(_ text:String){description=text}
}
struct PixelImage {
    var minX:Double;var minY:Double;var width:Int;var height:Int;var rgba:[UInt8]
}
final class MetalBackend {
    let device:MTLDevice
    let queue:MTLCommandQueue
    let compute:MTLComputePipelineState
    let present:MTLRenderPipelineState
    let textures:[MTLTexture]
    let initializationMs:Double
    let initializationStages:[String:Double]
    let shaderSHA256:String
    static let specs:[VectorEyeSpec] = [.left,.right]
    init() throws {
        let begin=CACurrentMediaTime()
        guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue() else {throw StudyFailure("No Metal device/queue. GPU evidence NOT produced; no CPU substitution.")}
        device=d;queue=q
        guard let url=ModuleBundle.url(named:ModuleBundle.appName,resource:"Eyes",ext:"metal",subdirectories:["Resources",nil]) else {throw StudyFailure("Missing copied Eyes.metal resource")}
        let data=try Data(contentsOf:url)
        shaderSHA256=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        let options=MTLCompileOptions()
        options.languageVersion = .version3_0
        options.fastMathEnabled=false // macOS13 API, unlike macOS15-only mathMode.
        let libraryStart=CACurrentMediaTime()
        let lib=try d.makeLibrary(source:String(decoding:data,as:UTF8.self),options:options)
        let libraryMs=(CACurrentMediaTime()-libraryStart)*1000
        guard let kernel=lib.makeFunction(name:"eyePixels"),let vertex=lib.makeFunction(name:"eyeQuad"),let fragment=lib.makeFunction(name:"eyePresent") else {throw StudyFailure("Missing MSL functions")}
        let computeStart=CACurrentMediaTime()
        compute=try d.makeComputePipelineState(function:kernel)
        let computeMs=(CACurrentMediaTime()-computeStart)*1000
        let p=MTLRenderPipelineDescriptor();p.vertexFunction=vertex;p.fragmentFunction=fragment
        let a=p.colorAttachments[0]!
        a.pixelFormat = .bgra8Unorm;a.isBlendingEnabled=true
        a.sourceRGBBlendFactor = .one;a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.sourceAlphaBlendFactor = .one;a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let renderStart=CACurrentMediaTime()
        present=try d.makeRenderPipelineState(descriptor:p)
        let renderMs=(CACurrentMediaTime()-renderStart)*1000
        let textureStart=CACurrentMediaTime()
        var images:[MTLTexture]=[]
        for spec in Self.specs {
            let b=SphereRasterBuffer.canvasBounds(spec:spec)
            let t=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:Int(b.maxX-b.minX),height:Int(b.maxY-b.minY),mipmapped:false)
            t.usage=[.shaderRead,.shaderWrite];t.storageMode = .shared
            guard let image=d.makeTexture(descriptor:t) else {throw StudyFailure("Eye texture allocation failed")}
            images.append(image)
        }
        textures=images;initializationMs=(CACurrentMediaTime()-begin)*1000
        initializationStages=["runtimeMakeLibraryMs":libraryMs,"makeComputePipelineMs":computeMs,"makeRenderPipelineMs":renderMs,"allocateEyeTexturesMs":(CACurrentMediaTime()-textureStart)*1000]
    }
    func encodePair(_ cb:MTLCommandBuffer,target:Point2D,legacy:Bool=false) throws {
        try encodePair(cb,heading:SafeGaze.heading(target:target),legacyTarget:legacy ? target:nil)
    }
    func encodePair(_ cb:MTLCommandBuffer,heading:Point2D,legacyTarget:Point2D?=nil) throws {
        guard let encoder=cb.makeComputeCommandEncoder() else {throw StudyFailure("No compute encoder")}
        encoder.setComputePipelineState(compute)
        let w=compute.threadExecutionWidth,h=max(1,min(8,compute.maxTotalThreadsPerThreadgroup/w))
        for (index,spec) in Self.specs.enumerated() {
            var u=EyeUniform(spec:spec,target:legacyTarget ?? SafeGaze.center)
            if legacyTarget==nil {let d=SafeGaze.direction(heading:heading);u.directionIris.x=Float(d.x);u.directionIris.y=Float(d.y);u.directionIris.z=Float(d.z)}
            encoder.setBytes(&u,length:MemoryLayout<EyeUniform>.stride,index:0)
            encoder.setTexture(textures[index],index:0)
            encoder.dispatchThreads(MTLSize(width:textures[index].width,height:textures[index].height,depth:1),threadsPerThreadgroup:MTLSize(width:w,height:h,depth:1))
        }
        encoder.endEncoding()
    }
    func encodePresentation(_ encoder:MTLRenderCommandEncoder,viewSize:CGSize) {
        encoder.setRenderPipelineState(present)
        let width=Double(viewSize.width),height=Double(viewSize.height)
        guard width>0,height>0 else{return}
        let map=WindowCanvasMap(width:width,height:height)
        for (i,spec) in Self.specs.enumerated() {
            let b=SphereRasterBuffer.canvasBounds(spec:spec)
            func nx(_ x:Double)->Float {Float(2*(map.origin.x+x*map.scale)/width-1)}
            func ny(_ y:Double)->Float {Float(1-2*(map.origin.y+y*map.scale)/height)}
            var q=SIMD4<Float>(nx(b.minX),ny(b.minY),nx(b.maxX),ny(b.maxY))
            encoder.setVertexBytes(&q,length:MemoryLayout<SIMD4<Float>>.stride,index:0)
            encoder.setFragmentTexture(textures[i],index:0)
            encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
        }
    }
    /// Only headless verification may synchronously wait or read pixels.
    func verifyPair(target:Point2D,readback:Bool=true,legacy:Bool=false,heading:Point2D?=nil) throws -> (images:[PixelImage],metrics:[String:Any]) {
        let start=CACurrentMediaTime()
        guard let cb=queue.makeCommandBuffer() else {throw StudyFailure("No verification command buffer")}
        if let heading {try encodePair(cb,heading:heading)}else{try encodePair(cb,target:target,legacy:legacy)}
        let before=CACurrentMediaTime();cb.commit();let after=CACurrentMediaTime()
        cb.waitUntilCompleted()
        let done=CACurrentMediaTime()
        guard cb.status == .completed else {throw StudyFailure("GPU verification failed: \(cb.error?.localizedDescription ?? "unknown")")}
        let plausible=StudyMetrics.hostTimesPlausible(encode:start,gpuStart:cb.gpuStartTime,gpuEnd:cb.gpuEndTime,callback:done)
        let metrics:[String:Any] = ["encodeMs":(before-start)*1000,"commitCallMs":(after-before)*1000,
            "gpuMs":cb.gpuStartTime>0 && cb.gpuEndTime>=cb.gpuStartTime ? ((cb.gpuEndTime-cb.gpuStartTime)*1000) as Any:NSNull(),"gpuStartHost":cb.gpuStartTime,"gpuEndHost":cb.gpuEndTime,"driverKernelStartHost":cb.kernelStartTime,"driverKernelEndHost":cb.kernelEndTime,
            "completedHost":done,"hostOrderingPlausible":plausible,"scope":"offscreen compute pair ONLY; no screen presentation or input latency"]
        return (readback ? readImages():[],metrics)
    }
    func readImages()->[PixelImage] {
        var images:[PixelImage]=[]
        for (index,spec) in Self.specs.enumerated() {
            let t=textures[index];var rgba=[UInt8](repeating:0,count:t.width*t.height*4)
            rgba.withUnsafeMutableBytes {raw in
                t.getBytes(raw.baseAddress!,bytesPerRow:t.width*4,from:MTLRegionMake2D(0,0,t.width,t.height),mipmapLevel:0)
            }
            let b=SphereRasterBuffer.canvasBounds(spec:spec)
            images.append(PixelImage(minX:b.minX,minY:b.minY,width:t.width,height:t.height,rgba:rgba))
        }
        return images
    }
}
#endif
