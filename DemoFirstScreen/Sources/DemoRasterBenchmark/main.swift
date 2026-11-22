import Foundation
import CryptoKit
import DemoFirstScreenCore

// Release-only finite benchmark. No AppKit, PNG, per-pixel clocks, input or disk scan.
func now() -> Double { ProcessInfo.processInfo.systemUptime }
func stats(_ x: [Double]) -> [String: Any] {
    let a = x.sorted(); return ["n": a.count, "p50Ms": a[a.count/2], "p95Ms": a[max(0,Int(ceil(Double(a.count)*0.95))-1)], "samplesMs": x]
}
func digest(_ x: [UInt8]) -> String { SHA256.hash(data: Data(x)).map { String(format:"%02x",$0) }.joined() }
let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
let layout = session.layout
let pictures = layout.pointOnRay(degrees:312,radiusFraction:0.55)
let projects = layout.pointOnRay(degrees:351,radiusFraction:0.55)
let mid = Point2D(x:(pictures.x+projects.x)*0.5,y:(pictures.y+projects.y)*0.5)
let targets: [(String,Point2D)] = [
    ("defaultMovies",SphereGaze.defaultTarget(sectors:session.chartability.sectors,layout:layout)),
    ("movies",layout.pointOnRay(degrees:200,radiusFraction:0.55)),
    ("archives",layout.pointOnRay(degrees:235,radiusFraction:0.55)),
    ("documents",layout.pointOnRay(degrees:270,radiusFraction:0.55)),
    ("pictures",pictures),("projects",projects),("joinMidpoint",mid),
    ("transparent",Point2D(x:80,y:80)),("letterbox",Point2D(x:-360,y:900))]
var coldPrepare:[Double]=[],coldTotal:[Double]=[]
var coldEqual = true
for _ in 0..<5 {
    let t=now();let l=SphereRasterBuffer.prepare(spec:.left),r=SphereRasterBuffer.prepare(spec:.right)
    let preparedAt=now();let p=targets[0].1
    let lb=SphereRasterBuffer.render(prepared:l,pose:SphereGaze.pose(spec:.left,target:p))
    let rb=SphereRasterBuffer.render(prepared:r,pose:SphereGaze.pose(spec:.right,target:p));let end=now()
    coldPrepare.append((preparedAt-t)*1000);coldTotal.append((end-t)*1000)
    coldEqual = coldEqual && lb.rgba == BaselineRaster.render(spec:.left,pose:SphereGaze.pose(spec:.left,target:p)).rgba
    coldEqual = coldEqual && rb.rgba == BaselineRaster.render(spec:.right,pose:SphereGaze.pose(spec:.right,target:p)).rgba
}
let preparedL=SphereRasterBuffer.prepare(spec:.left),preparedR=SphereRasterBuffer.prepare(spec:.right)
struct PairResult { var leftMs:Double;var rightMs:Double;var pairMs:Double;var l:[UInt8];var r:[UInt8] }
func pair(_ target:Point2D,_ candidate:Bool)->PairResult {
    let start=now()
    let l = candidate ? SphereRasterBuffer.render(prepared:preparedL,pose:SphereGaze.pose(spec:.left,target:target)).rgba : BaselineRaster.render(spec:.left,pose:SphereGaze.pose(spec:.left,target:target)).rgba
    let middle=now()
    let r = candidate ? SphereRasterBuffer.render(prepared:preparedR,pose:SphereGaze.pose(spec:.right,target:target)).rgba : BaselineRaster.render(spec:.right,pose:SphereGaze.pose(spec:.right,target:target)).rgba
    let end=now()
    return PairResult(leftMs:(middle-start)*1000,rightMs:(end-middle)*1000,pairMs:(end-start)*1000,l:l,r:r)
}
var consumer=0
for _ in 0..<3 { for c in [false,true] { let p=pair(targets[0].1,c);consumer += p.l.count+p.r.count } }
var records:[[String:Any]]=[],refL:[Double]=[],refR:[Double]=[],refP:[Double]=[],optL:[Double]=[],optR:[Double]=[],optP:[Double]=[]
var equal=coldEqual
for (name,target) in targets {
    var al:[Double]=[],ar:[Double]=[],ap:[Double]=[],bl:[Double]=[],br:[Double]=[],bp:[Double]=[]
    var hashes:[String]=[]
    for repeatIndex in 0..<5 {
        let a:PairResult,b:PairResult
        if repeatIndex%2==0 {a=pair(target,false);b=pair(target,true)} else {b=pair(target,true);a=pair(target,false)}
        // Full byte comparison + SHA outside ALL measured regions.
        equal = equal && a.l==b.l && a.r==b.r
        if repeatIndex==4 { hashes=[digest(a.l),digest(a.r),digest(b.l),digest(b.r)] }
        consumer += a.l.count+b.r.count
        al.append(a.leftMs);ar.append(a.rightMs);ap.append(a.pairMs)
        bl.append(b.leftMs);br.append(b.rightMs);bp.append(b.pairMs)
    }
    refL+=al;refR+=ar;refP+=ap;optL+=bl;optR+=br;optP+=bp
    // Also compare production entrypoint (bounded lazy cache), not just prepared API.
    let prodL=SphereRasterBuffer.render(spec:.left,pose:SphereGaze.pose(spec:.left,target:target)).rgba
    let prodR=SphereRasterBuffer.render(spec:.right,pose:SphereGaze.pose(spec:.right,target:target)).rgba
    equal = equal && digest(prodL)==hashes[0] && digest(prodR)==hashes[1]
    records.append(["name":name,"target":[target.x,target.y],"reference":["left":stats(al),"right":stats(ar),"pair":stats(ap)],"candidate":["left":stats(bl),"right":stats(br),"pair":stats(bp)],"sha256ReferenceLeftRightCandidateLeftRight":hashes])
}
// Whole-pass diagnostic probes, NOT additive stage percentages. Same original
// public math; one clock around each pass. No timing inside the pixel loop.
func kernel(_ kind:Int,_ spec:VectorEyeSpec,_ pose:SphericalEyePose)->Double {
    let b=SphereRasterBuffer.canvasBounds(spec:spec),e=spec.sclera
    let width=Int(b.maxX-b.minX),height=Int(b.maxY-b.minY),edge=1.6/min(e.radiusX,e.radiusY)
    var sum=0.0
    for row in 0..<height {
        let y=b.minY+Double(row)+0.5,uy=(y-e.center.y)/e.radiusY
        for col in 0..<width {
            let x=b.minX+Double(col)+0.5,ux=(x-e.center.x)/e.radiusX,r2=ux*ux+uy*uy
            switch kind {
            case 1:
                if r2>=1 || sqrt(r2)>1-edge { let c=EyeLidShade.sample(x:x,y:y,spec:spec);sum += (c.r+c.g)+(c.b+c.a) }
            case 2:
                if let h=SphereShade.wetSurfaceHit(unitX:ux,unitY:uy,dir:pose.direction,irisAlpha:pose.irisAngularRadius) {sum += h.point.x+h.point.y+h.point.z+h.normal.x+h.normal.y+h.normal.z+h.cornealWeight}
            case 3:
                let c=SphereShade.sample(unitX:ux,unitY:uy,dir:pose.direction,irisAlpha:pose.irisAngularRadius,pupilAlpha:pose.pupilAngularRadius,edgeWidth:edge);sum += (c.r+c.g)+(c.b+c.a)
            default:sum += ux+uy+r2
            }
        }
    }
    return sum
}
var probes:[[String:Any]]=[];var probeConsumer=0.0
for (name,p) in [targets[0],targets[5],targets[6]] {
    var values=[[Double]](repeating:[],count:4)
    for _ in 0..<5 {for k in 0..<4 {
        let t=now();let l=kernel(k,.left,SphereGaze.pose(spec:.left,target:p)),r=kernel(k,.right,SphereGaze.pose(spec:.right,target:p));let end=now()
        values[k].append((end-t)*1000);probeConsumer += l+r
    }}
    probes.append(["target":name,"loopChecksumControl":stats(values[0]),"fixedLidStandalone":stats(values[1]),"wetIntersectionStandalone":stats(values[2]),"wholeShaderStandalone":stats(values[3])])
}
var timerOverhead:[Double]=[]
for _ in 0..<1000 {let a=now(),b=now();timerOverhead.append((b-a)*1000)}
let report:[String:Any] = ["referenceNote":"161614 original loop; material and geometry math unchanged", "optimization":"fixed outside-globe final pixels + inside row spans; AA uses original Double lid/composite", "allRGBAZeroDiff":equal,"timing":"Release, no PNG/AppKit/log/hash in timed pair region; AB/BA alternating; p95 of5 is max; cold means application geometry-cache initialization, NOT CPU cache flush", "reference":["left":stats(refL),"right":stats(refR),"pair":stats(refP)],"candidate":["left":stats(optL),"right":stats(optR),"pair":stats(optP)],"coldPreparePair":stats(coldPrepare),"coldPreparePlusFirstPair":stats(coldTotal),"cacheMemory":["baseBytes":preparedL.baseByteCount+preparedR.baseByteCount,"arrayPayloadCapacityBytes":preparedL.payloadCapacityBytes+preparedR.payloadCapacityBytes,"spanCapacityBytes":preparedL.spanCapacityBytes+preparedR.spanCapacityBytes,"method":"Swift Array.capacity * MemoryLayout<Element>.stride; payload only, excludes headers/allocator/images/output; NOT RSS"],"perTarget":records,"standaloneProbes":probes,"probeCaveat":"Standalone kernels have checksum reductions and different output/store work. NOT instrumented stages of production and cannot be subtracted into material percentages. Control bounds loop/reduction cost only; no per-pixel clocks. Normal release optimizer may specialize them differently.","twoClockReadOverhead":stats(timerOverhead),"consumer":consumer,"probeConsumer":probeConsumer]
let dir=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("benchmark.json"))
print("allRGBAZeroDiff=\(equal) referencePairMedianMs=\(refP.sorted()[refP.count/2]) candidatePairMedianMs=\(optP.sorted()[optP.count/2])")
if !equal { exit(2) }
