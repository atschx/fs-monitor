// Exact 161614 reference loop, renamed only. Benchmark-only entrypoint.
// Kept in the SAME Core module as candidate to avoid cross-module call bias.
import Foundation

/// Top-down (canvas y-down) premultiplied RGBA buffer of one eye.
///
/// Row 0 is the *top* of the sclera bbox (`minY`). This matches SwiftUI Canvas
/// and `NSImage`/`CGImage` drawing, where the first buffer row is placed at the
/// top of the destination rect. 074605 wrote canvas-bottom into row 0 on the
/// assumption that "CGImage row 0 is the bottom"; cacheDisplay PNGs then showed
/// the iris above the globe while every platter target was below.
public enum BaselineRaster {
    public struct Buffer: Sendable {
        public var minX: Double
        public var minY: Double
        public var width: Int
        public var height: Int
        public var rgba: [UInt8]

        public var bytesPerRow: Int { width * 4 }
    }

    public static func canvasBounds(spec: VectorEyeSpec) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let e = spec.sclera, shell = spec.shell
        return (floor(min(e.minX, shell.minX)) - 1, floor(min(e.minY, shell.minY)) - 1,
                ceil(max(e.maxX, shell.maxX)) + 1, ceil(max(e.maxY, shell.maxY)) + 1)
    }

    public static func render(spec: VectorEyeSpec, pose: SphericalEyePose) -> Buffer {
        let b = canvasBounds(spec: spec)
        let width = max(0, Int(b.maxX - b.minX))
        let height = max(0, Int(b.maxY - b.minY))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard width > 2, height > 2 else {
            return Buffer(minX: b.minX, minY: b.minY, width: width, height: height, rgba: rgba)
        }

        let e = spec.sclera
        let edge = 1.6 / min(e.radiusX, e.radiusY)
        for row in 0..<height {
            // Row 0 = canvas top = minY. Do not invert.
            let y = b.minY + Double(row) + 0.5
            let unitY = (y - e.center.y) / e.radiusY
            let rowOff = row * width * 4
            for col in 0..<width {
                let x = b.minX + Double(col) + 0.5
                let unitX = (x - e.center.x) / e.radiusX
                let globe = SphereShade.sample(
                    unitX: unitX,
                    unitY: unitY,
                    dir: pose.direction,
                    irisAlpha: pose.irisAngularRadius,
                    pupilAlpha: pose.pupilAngularRadius,
                    edgeWidth: edge
                )
                let lid = globe.a < 1 ? EyeLidShade.sample(x: x, y: y, spec: spec) : .transparent
                let a = globe.a + lid.a * (1 - globe.a)
                if a <= 0 { continue }
                let back = lid.a * (1 - globe.a)
                let off = rowOff + col * 4
                rgba[off + 0] = u8(globe.r * globe.a + lid.r * back)
                rgba[off + 1] = u8(globe.g * globe.a + lid.g * back)
                rgba[off + 2] = u8(globe.b * globe.a + lid.b * back)
                rgba[off + 3] = u8(a)
            }
        }
        return Buffer(minX: b.minX, minY: b.minY, width: width, height: height, rgba: rgba)
    }

    /// Un-premultiplies one pixel; nil if out of bounds or transparent.
    public static func pixel(in buffer: Buffer, canvasX: Int, canvasY: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        let c = Int(floor(Double(canvasX) - buffer.minX))
        let r = Int(floor(Double(canvasY) - buffer.minY))
        guard r >= 0, r < buffer.height, c >= 0, c < buffer.width else { return nil }
        let off = r * buffer.bytesPerRow + c * 4
        let pr = Int(buffer.rgba[off + 0])
        let pg = Int(buffer.rgba[off + 1])
        let pb = Int(buffer.rgba[off + 2])
        let pa = Int(buffer.rgba[off + 3])
        if pa <= 0 { return (0, 0, 0, 0) }
        return (min(255, (pr * 255 + pa / 2) / pa), min(255, (pg * 255 + pa / 2) / pa), min(255, (pb * 255 + pa / 2) / pa), pa)
    }

    private static func u8(_ x: Double) -> UInt8 {
        let v = Int((max(0, min(1, x)) * 255).rounded())
        return UInt8(max(0, min(255, v)))
    }
}

