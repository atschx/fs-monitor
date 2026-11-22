import Foundation

public struct IdleContext:Equatable,Sendable {
    public var visible:Bool,focused:Bool,inside:Bool,reduced:Bool
    public init(visible:Bool=true,focused:Bool=true,inside:Bool=true,reduced:Bool=false){self.visible=visible;self.focused=focused;self.inside=inside;self.reduced=reduced}
    public var active:Bool {focused && inside}
    public var permitted:Bool {visible && !reduced}
}
public struct IdleSegment:Equatable,Sendable {
    public var from:Point2D,to:Point2D,start:Double,duration:Double
    public init(from:Point2D,to:Point2D,start:Double,duration:Double){self.from=from;self.to=to;self.start=start;self.duration=duration}
    public func point(at now:Double)->Point2D {
        if now<=start{return from};if now>=start+duration{return to}
        let t=min(1,max(0,(now-start)/duration)),e=t*t*t*(10+t*(-15+6*t))
        return Point2D(x:from.x+(to.x-from.x)*e,y:from.y+(to.y-from.y)*e)
    }
}
/// Pure monotonic-time policy; one external one-shot wake, no polling clock.
/// RNG advances only on accepted wake/finished segment. No cards/locks/input data.
public struct GazeIdle:Sendable {
    public private(set) var context=IdleContext()
    public private(set) var generation:UInt64=0
    public private(set) var deadline:Double?
    public private(set) var anchor:Point2D?
    public private(set) var segment:IdleSegment?
    public private(set) var awaitingReturn=false
    public private(set) var rngState:UInt64
    public var engaged:Bool {anchor != nil || segment != nil}
    public init(seed:UInt64=0x46534d6f6e69746f){rngState=seed}
    private mutating func random()->Double {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        return Double(rngState >> 11)/9007199254740992.0
    }
    private mutating func reset(now:Double){
        generation &+= 1;anchor=nil;segment=nil
        deadline=context.permitted && !awaitingReturn ? now+(context.active ? 6:10):nil
    }
    public mutating func configure(_ value:IdleContext,now:Double,awaitReturn:Bool=false){
        context=value;awaitingReturn=awaitReturn;reset(now:now)
    }
    public mutating func input(now:Double){awaitingReturn=false;reset(now:now)}
    public mutating func returnFinished(now:Double){
        guard awaitingReturn else{return};awaitingReturn=false
        generation &+= 1;deadline=context.permitted ? now+10:nil
    }
    @discardableResult public mutating func wake(token:UInt64,expectedDeadline:Double,now:Double,current:Point2D,settled:Bool)->Bool {
        guard token==generation,deadline==expectedDeadline,now>=expectedDeadline,context.permitted,!awaitingReturn,settled,segment==nil else{return false}
        if anchor==nil {anchor=SafeGaze.limited(current)}
        let amplitude=context.active ? 1+2*random():1.5*random(),azimuth=random()*2*Double.pi,duration=0.6+0.4*random()
        segment=IdleSegment(from:current,to:SafeGaze.offset(anchor:anchor!,degrees:amplitude,azimuth:azimuth),start:now,duration:duration)
        deadline=nil;return true
    }
    public mutating func sample(now:Double)->(point:Point2D,ended:Bool)? {
        guard let s=segment else{return nil};let point=s.point(at:now)
        if now>=s.start+s.duration {
            segment=nil;deadline=now+(context.active ? 6+6*random():15+10*random())
            return (point,true)
        }
        return (point,false)
    }
}
