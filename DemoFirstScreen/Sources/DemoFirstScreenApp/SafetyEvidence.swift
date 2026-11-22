#if os(macOS)
import AppKit
import CryptoKit
import DemoFirstScreenCore
import EyeStudySupport

enum SafetyEvidence {
    static func hash(_ p:PixelImage)->String{SHA256.hash(data:Data(p.rgba)).map{String(format:"%02x",$0)}.joined()}
    static func write(backend:MetalBackend,example:DemoSnapshot,to folder:URL)throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var canonical:[[String:Any]]=[]
        for pose in StudyPose.allCases {
            let target=try pose.target(),legacy=try backend.verifyPair(target:target,legacy:true).images
            canonical.append(["pose":pose.rawValue,"GPUrawSHA256":legacy.map(hash),"scope":"EXACT frozen legacy direction/uniform input; shader/material unchanged. NOT forcing old convergence onto new target mapping."])
        }
        try JSONSerialization.data(withJSONObject:canonical,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("legacy-uniform-material-canonical.json"))
        let cases:[(String,Point2D)]=[("center",SafeGaze.center),("nose-bridge",Point2D(x:1203,y:405)),("left-window-edge",Point2D(x:20,y:482)),("right-window-edge",Point2D(x:2380,y:482))]
        var reports:[[String:Any]]=[]
        for (name,target) in cases {
            let h=SafeGaze.heading(target:target),capture=try backend.verifyPair(target:target),legacy=try backend.verifyPair(target:target,legacy:true).images
            var session=InteractionSession(snapshot:example);session.pointerMoved(to:target)
            var full=try GPUIntegrationEvidence.render(session,part:.withoutEyes)
            for im in capture.images{GPUIntegrationEvidence.over(im,&full)}
            try GPUIntegrationEvidence.fullPNG(full,to:folder.appendingPathComponent("full-\(name)-SAFE-GPU-plus-SwiftUI-NOT-SCREENSHOT.png"))
            try writePNG(pairComposite(capture.images),to:folder.appendingPathComponent("native-\(name)-SAFE-GPU-pair.png"))
            try writePNG(pairComposite(legacy),to:folder.appendingPathComponent("native-\(name)-LEGACY-GPU-pair.png"))
            try writePNG(checkerComparison(cpu:pairComposite(legacy),gpu:pairComposite(capture.images)),to:folder.appendingPathComponent("native-\(name)-LEGACY-left-SAFE-right.png"))
            let l=SafeGaze.pose(spec:.left,heading:h),rr=SafeGaze.pose(spec:.right,heading:h)
            reports.append(["case":name,"rawUITarget":[target.x,target.y],"headingUnits":[h.x,h.y],"directionL":[l.direction.x,l.direction.y,l.direction.z],"directionR":[rr.direction.x,rr.direction.y,rr.direction.z],"exactConjugate":l.direction==rr.direction,"legacyDirectionL":[SphereGaze.pose(spec:.left,target:target).direction.x,SphereGaze.pose(spec:.left,target:target).direction.y],"legacyDirectionR":[SphereGaze.pose(spec:.right,target:target).direction.x,SphereGaze.pose(spec:.right,target:target).direction.y]])
        }
        var trajectory:[[String:Any]]=[]
        var motion=SharedGazeMotion(target:SafeGaze.heading(target:Point2D(x:400,y:482)),time:0)
        motion.retarget(SafeGaze.heading(target:Point2D(x:1920,y:482)),at:0,reduced:false)
        for (i,t) in [0.0,0.015,0.03,0.045,0.06,0.075,0.09,0.11,0.14,0.18,0.23,0.29,0.36,0.44,0.53,0.63,0.75].enumerated(){
            let h=motion.advance(to:t),ims=try backend.verifyPair(target:SafeGaze.center,heading:h).images
            try writePNG(pairComposite(ims),to:folder.appendingPathComponent(String(format:"native-center-cross-%02d-GPU.png",i)))
            let d=SafeGaze.direction(heading:h);trajectory.append(["frame":i,"analyticTime":t,"headingUnits":[h.x,h.y],"direction":[d.x,d.y,d.z],"scope":"same spring, synthetic time OFFSCREEN Metal readback, not OS or presented live frame"])
        }
        var extremes:[[String:Any]]=[]
        for (name,anchor) in [("center",SafeGaze.heading(target:SafeGaze.center)),("right",SafeGaze.heading(target:Point2D(x:2380,y:482)))] {
            for i in 0..<4 {
                let h=SafeGaze.offset(anchor:anchor,degrees:3,azimuth:Double(i)*Double.pi/2),ims=try backend.verifyPair(target:SafeGaze.center,heading:h).images
                try writePNG(pairComposite(ims),to:folder.appendingPathComponent("native-idle-extreme-\(name)-\(i)-GPU.png"))
                let d=SafeGaze.direction(heading:h);extremes.append(["anchor":name,"i":i,"headingUnits":[h.x,h.y],"direction":[d.x,d.y,d.z],"offsetDegrees":hypot(h.x-anchor.x,h.y-anchor.y)/SafeGaze.unitsPerRadian*180/Double.pi])
            }
        }
        let report:[String:Any]=["cases":reports,"centerCrossing":trajectory,"idleExtremes":extremes,"shaderSHA256":backend.shaderSHA256,"mapping":"Conjugate far-field heading from shared cyclopean center; analytic nearfield attenuation, radial tanh soft limit42deg, scaled angular motion. NOT just Z adjustment or hard center deadzone.","scope":"Actual Metal at native638x726/692x700. Full images are real SwiftUI underlay + GPU texture readback, NOT GUI screenshot. Idle extreme/trajectory are deterministic OFFSCREEN, distinct from live timer captures.","friendlinessAcceptedByHuman":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("safety-evidence-report.json"))
    }
}
#endif
