import Foundation

/// Fixed ellipsoidal shell with a softly rolled aperture, lit in the same
/// eye-space as the globe. It is a procedural stylized lid, not anatomical
/// simulation. No screen-space oval shadow plate or duplicate dark-red outline.
public enum EyeLidShade {
    public static func sample(x: Double, y: Double, spec: VectorEyeSpec) -> SphereShade.RGBA {
        let shell = spec.shell, e = spec.sclera
        let u = (x - shell.center.x) / shell.radiusX
        let v = (y - shell.center.y) / shell.radiusY
        let rho2 = u * u + v * v
        guard rho2 < 1 else { return .transparent }
        let z = sqrt(1 - rho2)
        let n = Vec3(u, v, z * 1.12).normalized()
        let lambert = max(0, Vec3.dot(n, SphereShade.light))
        let half = (SphereShade.light + SphereShade.view).normalized()
        let specular = 0.08 * pow(max(0, Vec3.dot(n, half)), 26)
        let limb = pow(1 - z, 2)
        var shade = (0.71 + 0.29 * lambert) * (1 - 0.15 * limb)
        let gx = (x - e.center.x) / e.radiusX
        let gy = (y - e.center.y) / e.radiusY
        let distance = max(0, sqrt(gx * gx + gy * gy) - 1)
        // Small rounded bead at the aperture: soft highlight shoulder followed
        // by a narrow warm contact crease. Distance derives from the actual
        // sclera boundary, so it hugs the globe instead of crossing its face.
        let bead = exp(-pow((distance - 0.025) / 0.019, 2))
        let crease = exp(-pow(distance / 0.010, 2))
        let upperLight = max(0, min(1, 0.6 - gy * 0.35 - gx * 0.20))
        shade *= 1 - 0.24 * crease
        let lift = bead * (0.08 + upperLight * 0.14)
        let a = max(0, min(1, (1 - sqrt(rho2)) * min(shell.radiusX, shell.radiusY) / 1.4))
        return SphereShade.RGBA(r: min(1, 0.902 * shade + specular + lift),
                               g: min(1, 0.796 * shade + specular + lift),
                               b: min(1, 0.702 * shade + specular + lift), a: a)
    }
}
