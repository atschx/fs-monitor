import Foundation

/// 18:30 intentional behavior change. Conjugate far-field heading, not two
/// near-eye rays aimed at the nose. Legacy SphereGaze stays as frozen reference.
public enum SafeGaze {
    public static let center = Point2D(x:1161,y:482)
    public static let unitsPerRadian = 1400.0
    public static let limitRadians = 42.0 * Double.pi / 180
    public static var maxUnits:Double {limitRadians*unitsPerRadian}
    public static func heading(target:Point2D)->Point2D {
        let x=(target.x-center.x)/273,y=(target.y-center.y)/289,r=hypot(x,y)
        guard r>1e-12 else{return Point2D(x:0,y:0)}
        // Analytic, positive derivative near center: no hard dead zone or snap.
        let near=0.18+0.82*(1-exp(-r*r/(1.2*1.2)))
        let angle=limitRadians*tanh(atan2(r*near,5)/limitRadians)
        return Point2D(x:x/r*angle*unitsPerRadian,y:y/r*angle*unitsPerRadian)
    }
    public static func limited(_ p:Point2D)->Point2D {
        let n=hypot(p.x,p.y);guard n>maxUnits else{return p}
        return Point2D(x:p.x*maxUnits/n,y:p.y*maxUnits/n)
    }
    public static func direction(heading:Point2D)->Vec3 {
        let p=limited(heading),n=hypot(p.x,p.y)
        guard n>1e-12 else{return Vec3(0,0,1)}
        let angle=n/unitsPerRadian,s=sin(angle)
        return Vec3(s*p.x/n,s*p.y/n,cos(angle))
    }
    public static func offset(anchor:Point2D,degrees:Double,azimuth:Double)->Point2D {
        let d=degrees*Double.pi/180*unitsPerRadian
        return limited(Point2D(x:anchor.x+cos(azimuth)*d,y:anchor.y+sin(azimuth)*d))
    }
    public static func pose(spec:VectorEyeSpec,heading:Point2D)->SphericalEyePose {
        var p=SphereGaze.pose(spec:spec,target:center)
        let d=direction(heading:heading),rx=spec.sclera.radiusX,ry=spec.sclera.radiusY
        let u=Vec3.cross(Vec3(0,1,0),d).normalized(),v=Vec3.cross(d,u).normalized()
        p.direction=d;p.facing=d.z
        p.projectedIrisCenter=Point2D(x:p.scleraCenter.x+d.x*cos(p.irisAngularRadius)*rx,y:p.scleraCenter.y+d.y*cos(p.irisAngularRadius)*ry)
        p.projectedPupilCenter=Point2D(x:p.scleraCenter.x+d.x*cos(p.pupilAngularRadius)*rx,y:p.scleraCenter.y+d.y*cos(p.pupilAngularRadius)*ry)
        p.irisAxisU=Point2D(x:u.x*sin(p.irisAngularRadius)*rx,y:u.y*sin(p.irisAngularRadius)*ry)
        p.irisAxisV=Point2D(x:v.x*sin(p.irisAngularRadius)*rx,y:v.y*sin(p.irisAngularRadius)*ry)
        p.projectedPupilAxisU=Point2D(x:u.x*sin(p.pupilAngularRadius)*rx,y:u.y*sin(p.pupilAngularRadius)*ry)
        p.projectedPupilAxisV=Point2D(x:v.x*sin(p.pupilAngularRadius)*rx,y:v.y*sin(p.pupilAngularRadius)*ry)
        return p
    }
}
