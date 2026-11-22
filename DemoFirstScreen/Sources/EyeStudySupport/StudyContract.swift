import Foundation
import DemoFirstScreenCore

/// CPU Double geometry remains the reference. Only the GPU ABI casts to FP32.
public struct EyeUniform: Sendable {
    public var bounds: SIMD4<Float>
    public var sclera: SIMD4<Float>
    public var shell: SIMD4<Float>
    public var directionIris: SIMD4<Float>
    public var pupilEdge: SIMD4<Float>
    public init(spec: VectorEyeSpec, target: Point2D) {
        let b = SphereRasterBuffer.canvasBounds(spec: spec)
        let p = SphereGaze.pose(spec: spec, target: target)
        bounds = SIMD4(Float(b.minX), Float(b.minY), Float(b.maxX-b.minX), Float(b.maxY-b.minY))
        sclera = SIMD4(Float(spec.sclera.center.x),Float(spec.sclera.center.y),Float(spec.sclera.radiusX),Float(spec.sclera.radiusY))
        shell = SIMD4(Float(spec.shell.center.x),Float(spec.shell.center.y),Float(spec.shell.radiusX),Float(spec.shell.radiusY))
        directionIris = SIMD4(Float(p.direction.x),Float(p.direction.y),Float(p.direction.z),Float(p.irisAngularRadius))
        pupilEdge = SIMD4(Float(p.pupilAngularRadius),Float(1.6/min(spec.sclera.radiusX,spec.sclera.radiusY)),0,0)
    }
}
public enum StudyPose: String, CaseIterable, Sendable {
    case moviesDefault, projects, joinMidpoint
    public static func defaultTarget() throws -> Point2D {
        let s = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        return SphereGaze.defaultTarget(sectors:s.chartability.sectors,layout:s.layout)
    }
    public func target() throws -> Point2D {
        let layout = SemicircleLayout.selectedBase
        let p = layout.pointOnRay(degrees:351,radiusFraction:0.55)
        switch self {
        case .moviesDefault: return try Self.defaultTarget()
        case .projects: return p
        case .joinMidpoint:
            let a=layout.pointOnRay(degrees:312,radiusFraction:0.55)
            return Point2D(x:(a.x+p.x)*0.5,y:(a.y+p.y)*0.5)
        }
    }
}
public enum SignalKind: String, Sendable {
    case localPointer = "os-local-pointer", localExit = "os-local-exit"
    case preset, synthetic = "synthetic-goal-NOT-OS-input"
}
public struct SignalContext: Sendable {
    public var id: Int
    public var kind: SignalKind
    public var receivedHost: Double
    public var rawEventTimestamp: Double?
    public var goal: Point2D
    public var counterfactual: SharedGazeMotion
    public init(id:Int,kind:SignalKind,receivedHost:Double,rawEventTimestamp:Double?,goal:Point2D,previous:SharedGazeMotion) {
        self.id=id;self.kind=kind;self.receivedHost=receivedHost
        self.rawEventTimestamp=rawEventTimestamp;self.goal=goal
        counterfactual=previous;counterfactual.advance(to:receivedHost)
    }
    public func influenceDistance(at host:Double,shown:Point2D)->Double {
        var old=counterfactual;old.advance(to:host)
        return hypot(shown.x-old.position.x,shown.y-old.position.y)
    }
}
public enum StudyMetrics {
    /// Empirical nearest-rank percentile. Empty samples are not zero latency.
    public static func percentile(_ samples:[Double],_ q:Double)->Double? {
        let s=samples.filter(\.isFinite).sorted();guard !s.isEmpty else{return nil}
        return s[min(s.count-1,max(0,Int(ceil(Double(s.count)*q))-1))]
    }
    public static func stats(_ samples:[Double])->[String:Any] {
        let s=samples.filter(\.isFinite)
        return ["n":s.count,"p50":percentile(s,0.5).map { $0 as Any } ?? NSNull(),"p95":percentile(s,0.95).map { $0 as Any } ?? NSNull()]
    }
    public static func hostTimesPlausible(encode:Double,gpuStart:Double,gpuEnd:Double,callback:Double)->Bool {
        gpuStart>0 && gpuEnd>=gpuStart && gpuStart>=encode-0.050 && gpuEnd<=callback+0.050
    }
    public static func presentedPlausible(encode:Double,presented:Double,callback:Double)->Bool {
        presented>0 && presented>=encode-0.050 && presented<=callback+0.050
    }
}
