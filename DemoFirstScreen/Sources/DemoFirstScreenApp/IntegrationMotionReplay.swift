#if os(macOS)
import Foundation
import DemoFirstScreenCore
import EyeStudySupport
/// Independent replay of logged heading units, original spring and idle polynomial.
enum IntegrationMotionReplay {
    static func audit(_ rows:[[String:Any]],truncated:Bool)->[String:Any]{
        do {
            var model=SharedGazeMotion(target:SafeGaze.heading(target:try StudyPose.defaultTarget()),time:0)
            var segment:IdleSegment?,count=0,maxError=0.0,idleCount=0
            func point(_ value:Any?)->Point2D?{guard let v=value as? [Double],v.count==2 else{return nil};return Point2D(x:v[0],y:v[1])}
            for r in rows {
                let type=r["type"] as? String
                if type=="motion-reset",let p=point(r["point"]),let t=r["host"]as? Double {model=SharedGazeMotion(target:p,time:t);segment=nil}
                else if type=="goal",let p=point(r["target"]),let t=r["receivedHost"]as? Double {model.retarget(p,at:t,reduced:r["reducedMotion"]as? Bool ?? false);segment=nil}
                else if type=="idle-segment-begin",let a=point(r["from"]),let b=point(r["to"]),let t=r["start"]as? Double,let d=r["duration"]as? Double {segment=IdleSegment(from:a,to:b,start:t,duration:d)}
                else if type=="submitted",let t=r["encodeStartHost"]as? Double,let shown=point(r["shownTarget"]) {
                    let expected:Point2D
                    if let s=segment {expected=s.point(at:t);idleCount+=1}else{expected=model.advance(to:t)}
                    maxError=max(maxError,hypot(shown.x-expected.x,shown.y-expected.y));count+=1
                }
            }
            return ["samples":count,"idleSamples":idleCount,"maxHeadingUnitError":maxError,"logTruncated":truncated,"passed":count>0 && !truncated && maxError<1e-9,"scope":"Same actual goal/sample times, explicit resets, unchanged spring and idle quintic. Heading units1400/radian, NOT old per-eye near rays, pixel or physical-input proof."]
        }catch{return["passed":false,"error":String(describing:error)]}
    }
}
#endif
