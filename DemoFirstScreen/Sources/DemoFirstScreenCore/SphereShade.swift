import Foundation

/// Analytic orthographic eye: unit sclera plus a C1 smooth-union spherical
/// corneal dome. A camera ray hits the continuous wet surface, refracts into
/// the aqueous medium and reaches the recessed iris plane. The highlight is a
/// finite light reflected by that actual dome normal, never a screen-space dot.
/// Procedural material referencing D2, not a pixel reconstruction of D2.
public enum SphereShade {
    public struct RGBA: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double
        public var a: Double

        public static let transparent = RGBA(r: 0, g: 0, b: 0, a: 0)
    }

    /// Light from upper-left, toward the camera, matching the D2 key light.
    public static let light = Vec3(-0.28, -0.32, 0.90).normalized()
    public static let view = Vec3(0, 0, 1)

    /// Shade one unit-disc sample. `unitX`/`unitY` are (canvas − center) / radii.
    /// `edgeWidth` is the silhouette AA width in unit-sphere coordinates.
    public static func sample(
        unitX: Double,
        unitY: Double,
        dir: Vec3,
        irisAlpha: Double,
        pupilAlpha: Double,
        edgeWidth: Double
    ) -> RGBA {
        let rho2 = unitX * unitX + unitY * unitY
        if rho2 >= 1 { return .transparent }
        let z = (1 - rho2).squareRoot()
        let p = Vec3(unitX, unitY, z)
        let rho = rho2.squareRoot()
        var coverage = 1.0
        if edgeWidth > 1e-9, rho > 1 - edgeWidth {
            coverage = max(0, (1 - rho) / edgeWidth)
            coverage = coverage * coverage * (3 - 2 * coverage)
        }

        let hit = wetSurfaceHit(unitX: unitX, unitY: unitY, dir: dir, irisAlpha: irisAlpha)
        let nDotL = max(0, Vec3.dot(p, light))
        let rim = pow(1 - z, 2.0)
        let scleraColor = mix(Material.sclera, Material.scleraShade, 0.26 * rim)
        let scleraShade = (0.76 + 0.24 * nDotL) * (1 - 0.13 * rim)
        var albedo = scleraColor
        var shade = scleraShade
        var spec = 0.0
        if let hit {
            // A continuous tear film coats BOTH sclera and cornea. Reflection
            // is never switched off by iris visibility or a boolean cap gate.
            // Roughness transitions continuously with the smooth geometry.
            let eta = 1.0 / 1.336
            let ci = max(0, hit.normal.z)
            let ct = sqrt(max(0, 1 - eta * eta * (1 - ci * ci)))
            let transmitted = Vec3(0, 0, -eta) + hit.normal * (eta * ci - ct)
            let plane = cos(irisAlpha)
            let denom = Vec3.dot(transmitted, dir)
            let t = (plane - Vec3.dot(hit.point, dir)) / min(-1e-8, denom)
            let irisPoint = hit.point + transmitted * max(0, t)
            let axial = Vec3.dot(irisPoint, dir)
            let radial = (irisPoint - dir * axial).length
            let polar = asin(min(0.99999, radial))
            // Opacity at the anatomical limbus is independent of the geometry
            // join. The iris radius is unchanged; its edge softens INWARD, never
            // enlarged to cover a gap. Outer sclera remains opaque underneath
            // the same transparent tear-film reflection.
            let irisEdge = 1 - smoothstep(sin(irisAlpha) - 0.020, sin(irisAlpha), radial)
            let clearCornea = smoothstep(plane - 0.025, plane + 0.025, Vec3.dot(hit.point, dir))
            let visibility = irisEdge * clearCornea
            if visibility > 0 {
                let tissue = irisAlbedo(polar: polar, irisAlpha: irisAlpha, pupilAlpha: pupilAlpha, point: irisPoint, dir: dir)
                let irisColor = mix(Material.pupil, tissue, smoothstep(pupilAlpha - 0.008, pupilAlpha + 0.008, polar))
                let v = axisV(dir, u: axisU(dir))
                let localY = Vec3.dot(irisPoint, v) / max(0.01, sin(irisAlpha))
                let irisShade = (0.82 + 0.18 * max(0, Vec3.dot(dir, light))) * (0.84 + 0.16 * smoothstep(-0.8, 0.4, localY))
                // Blend lit substrate colors, not one abrupt lighting branch.
                albedo = mix(scaled(scleraColor, scleraShade), scaled(irisColor, irisShade), visibility)
                shade = 1
            }
            spec = wetReflection(normal: hit.normal, cornealWeight: hit.cornealWeight)
        }
        // The stationary lid contacts only a narrow geodesic rim of the globe.
        // Smooth falloff in distance from the aperture, never an overlaid ellipse.
        let upper = (1 - smoothstep(-0.75, 0.25, unitY))
        let gap = max(0, 1 - rho)
        let contact = (0.10 + 0.27 * upper) * exp(-gap / 0.022)
        shade *= 1 - contact
        return RGBA(
            r: min(1, albedo.0 * shade * (1 - min(1, spec)) + spec),
            g: min(1, albedo.1 * shade * (1 - min(1, spec)) + spec),
            b: min(1, albedo.2 * shade * (1 - min(1, spec)) + spec),
            a: coverage
        )
    }

    public struct CorneaHit: Sendable {
        public var point: Vec3
        public var normal: Vec3
        public var cornealWeight: Double
    }

    /// Width in unit-eye SDF coordinates. Polynomial smooth union is C1 in
    /// position/normal; this is actual ray-intersected geometry, not a shading
    /// normal lerp over the old sharp two-sphere visibility gate.
    public static let joinWidth = 0.080

    /// Continuous wet-coat reflection; NEVER conditional on iris albedo/cap.
    /// Light and emitter size are unchanged from 080440.
    public static func wetReflection(normal: Vec3, cornealWeight: Double = 1) -> Double {
        let ci = max(0, normal.z)
        let reflectedView = normal * (2 * ci) - view
        let key = smoothstep(cos(0.36), cos(0.25), Vec3.dot(reflectedView, light))
        let fresnel = 0.0204 + 0.9796 * pow(1 - ci, 5)
        let half = (light + view).normalized()
        let sharp = min(1, key * fresnel * 54) + 0.045 * pow(max(0, Vec3.dot(normal, half)), 18)
        // Sclera tear film is microscopically rougher than the clear cornea.
        // Match 080440's weak broad scleral sheen, with a continuous transition
        // over the actual SDF join; no boolean cap/material visibility mask.
        let rough = 0.035 * pow(max(0, Vec3.dot(normal, half)), 38)
        let w = max(0, min(1, cornealWeight))
        return rough * (1 - w) + sharp * w
    }

    /// Analytic roots bracket the front root of the smooth-union SDF. Outside
    /// the join the exact sphere root is used. Inside it, bisection follows the
    /// same implicit surface whose analytic gradient provides the normal.
    /// Fixed circular aperture (rho<1) is real lid occlusion and is preserved.
    public static func wetSurfaceHit(unitX: Double, unitY: Double, dir: Vec3, irisAlpha: Double) -> CorneaHit? {
        let rho2 = unitX * unitX + unitY * unitY
        guard rho2 < 1 else { return nil }
        let c = dir * 0.50
        let radius = sqrt(1.25 - cos(irisAlpha))
        let dx = unitX - c.x, dy = unitY - c.y
        let disc = radius * radius - dx * dx - dy * dy
        let scleraZ = sqrt(1 - rho2)
        var z = scleraZ
        if disc >= 0 { z = max(z, c.z + sqrt(disc)) }
        var q = Vec3(unitX, unitY, z)
        var f = surfaceField(q, center: c, radius: radius)
        if abs(f.value) > 1e-9 {
            var lo = z
            var hi = max(1.0, c.z + radius) + joinWidth
            for _ in 0..<18 {
                let mid = (lo + hi) * 0.5
                let value = surfaceField(Vec3(unitX, unitY, mid), center: c, radius: radius).value
                if value > 0 { hi = mid } else { lo = mid }
            }
            z = (lo + hi) * 0.5
            q = Vec3(unitX, unitY, z)
            f = surfaceField(q, center: c, radius: radius)
        }
        return CorneaHit(point: q, normal: f.normal, cornealWeight: f.weight)
    }

    private static func surfaceField(_ q: Vec3, center: Vec3, radius: Double) -> (value: Double, normal: Vec3, weight: Double) {
        let a = q.length - 1
        let b = (q - center).length - radius
        let w = max(0, min(1, 0.5 + 0.5 * (a - b) / joinWidth))
        let value = a * (1 - w) + b * w - joinWidth * w * (1 - w)
        // Exact gradient of polynomial smooth-min: derivatives of w cancel.
        let normal = (q.normalized() * (1 - w) + (q - center).normalized() * w).normalized()
        return (value, normal, w)
    }

    /// Compatibility for callers interested specifically in the dome/join.
    /// The renderer uses wetSurfaceHit for the whole continuous wet surface.
    public static func corneaHit(unitX: Double, unitY: Double, dir: Vec3, irisAlpha: Double) -> CorneaHit? {
        guard let hit = wetSurfaceHit(unitX: unitX, unitY: unitY, dir: dir, irisAlpha: irisAlpha), hit.cornealWeight > 0 else { return nil }
        return hit
    }

    private static func scaled(_ a: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
        (a.0 * k, a.1 * k, a.2 * k)
    }

    /// Cosine of the angle between the surface normal and the half-vector.
    /// Used to test that the highlight belongs to the sphere, not a screen disc.
    public static func specularAlignment(unitX: Double, unitY: Double) -> Double {
        let rho2 = unitX * unitX + unitY * unitY
        if rho2 >= 1 { return 0 }
        let p = Vec3(unitX, unitY, (1 - rho2).squareRoot())
        let half = (light + view).normalized()
        return max(0, Vec3.dot(p, half))
    }

    public static func isOnGlobe(unitX: Double, unitY: Double) -> Bool {
        unitX * unitX + unitY * unitY < 1
    }

    public static func isInIrisCap(
        unitX: Double,
        unitY: Double,
        dir: Vec3,
        irisAlpha: Double
    ) -> Bool {
        let rho2 = unitX * unitX + unitY * unitY
        if rho2 >= 1 { return false }
        let p = Vec3(unitX, unitY, (1 - rho2).squareRoot())
        let mu = max(-1, min(1, Vec3.dot(p, dir)))
        return acos(mu) <= irisAlpha
    }

    private enum Material {
        // Same family as VectorEyeSpec.Fill, written as linear-ish 0–1 triples
        // so Core stays Foundation-only. Sourced from the D2 rest appearance.
        static let sclera = (0.984, 0.965, 0.933)
        static let scleraShade = (0.910, 0.847, 0.769)
        static let irisInner = (0.227, 0.110, 0.047)
        static let irisMid = (0.553, 0.322, 0.149)
        static let irisFiber = (0.659, 0.416, 0.208)
        static let irisFiberDark = (0.361, 0.188, 0.078)
        static let irisGold = (0.769, 0.604, 0.322)
        static let irisLimbusEdge = (0.290, 0.141, 0.063)
        static let pupil = (0.078, 0.047, 0.031)
    }

    private static func irisAlbedo(
        polar: Double,
        irisAlpha: Double,
        pupilAlpha: Double,
        point: Vec3,
        dir: Vec3
    ) -> (Double, Double, Double) {
        let span = max(irisAlpha - pupilAlpha, 1e-6)
        let t = max(0, min(1, (polar - pupilAlpha) / span))
        let u = axisU(dir)
        let v = axisV(dir, u: u)
        let az = atan2(Vec3.dot(point, v), Vec3.dot(point, u))
        let wavy = az + 0.17 * sin(az * 6.0) + 0.09 * sin(az * 17.0 + 1.1)
        // Dense implied meridians, not a handful of thick 2D strokes.
        // Soft radial tissue, not denser meridians — D2 is a wet brown cap, not a lined disc.
        let bundle = 0.5 + 0.5 * sin(wavy * 28)
        let fine = 0.5 + 0.5 * sin(wavy * 64 + 0.6)
        let fiber = 0.7 * bundle + 0.3 * fine
        var base = mix(Material.irisInner, Material.irisMid, smoothstep(0.05, 0.55, t))
        base = mix(base, Material.irisFiber, smoothstep(0.35, 0.78, t) * 0.55)
        let fiberCol = mix(Material.irisFiberDark, Material.irisGold, 0.25 + 0.35 * t)
        base = mix(base, fiberCol, max(0, fiber - 0.42) * 0.28)
        // Gold-brown limbus as an angular band on the sphere, then a darker edge.
        base = mix(base, Material.irisGold, smoothstep(0.78, 0.90, t) * 0.85)
        base = mix(base, Material.irisLimbusEdge, smoothstep(0.90, 1.0, t))
        return base
    }

    private static func axisU(_ dir: Vec3) -> Vec3 {
        var u = Vec3.cross(Vec3(0, 1, 0), dir)
        if u.length < 1e-6 { u = Vec3(1, 0, 0) }
        return u.normalized()
    }

    private static func axisV(_ dir: Vec3, u: Vec3) -> Vec3 {
        Vec3.cross(dir, u).normalized()
    }

    private static func mix(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double),
        _ t: Double
    ) -> (Double, Double, Double) {
        let u = max(0, min(1, t))
        return (a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u, a.2 + (b.2 - a.2) * u)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / max(edge1 - edge0, 1e-9)))
        return t * t * (3 - 2 * t)
    }
}
