import Foundation

/// Top-down (canvas y-down) premultiplied RGBA buffer of one eye.
///
/// Row 0 is the *top* of the sclera bbox (`minY`). This matches SwiftUI Canvas
/// and `NSImage`/`CGImage` drawing, where the first buffer row is placed at the
/// top of the destination rect. 074605 wrote canvas-bottom into row 0 on the
/// assumption that "CGImage row 0 is the bottom"; cacheDisplay PNGs then showed
/// the iris above the globe while every platter target was below.
public enum SphereRasterBuffer {
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

    /// Bounded immutable geometry cache: final 8-bit pixels ONLY outside the
    /// globe, and exact integer spans inside. AA is still computed in Double
    /// by the original shader/lid/composite path, never from the 8-bit base.
    public struct Prepared: Sendable {
        fileprivate var spec: VectorEyeSpec
        fileprivate var bounds: (Double, Double, Double, Double)
        fileprivate var width: Int
        fileprivate var height: Int
        fileprivate var base: [UInt8]
        fileprivate var spans: [Span]
        public var baseByteCount: Int { base.count }
        public var baseCapacityBytes: Int { base.capacity * MemoryLayout<UInt8>.stride }
        public var spanCapacityBytes: Int { spans.capacity * MemoryLayout<Span>.stride }
        public var payloadCapacityBytes: Int { baseCapacityBytes + spanCapacityBytes }
    }
    fileprivate struct Span: Sendable { var start: Int; var end: Int }
    private static let leftPrepared = prepare(spec: .left)
    private static let rightPrepared = prepare(spec: .right)

    public static func prepare(spec: VectorEyeSpec) -> Prepared {
        let b = canvasBounds(spec: spec), e = spec.sclera
        let width = max(0, Int(b.maxX-b.minX)), height = max(0, Int(b.maxY-b.minY))
        var base = [UInt8](repeating: 0, count: width*height*4)
        var spans = [Span](repeating: Span(start: 0, end: 0), count: height)
        if width > 2, height > 2 {
            for row in 0..<height {
                let y = b.minY + Double(row) + 0.5
                let unitY = (y-e.center.y)/e.radiusY
                var start = width, end = 0
                for col in 0..<width {
                    let x = b.minX + Double(col) + 0.5
                    let unitX = (x-e.center.x)/e.radiusX
                    if unitX*unitX + unitY*unitY < 1 {
                        start = min(start, col); end = col+1
                        continue
                    }
                    let globe = SphereShade.RGBA.transparent
                    let lid = EyeLidShade.sample(x: x, y: y, spec: spec)
                    let alpha = globe.a + lid.a * (1-globe.a)
                    if alpha <= 0 { continue }
                    let back = lid.a * (1-globe.a), off = (row*width+col)*4
                    base[off+0] = u8(globe.r*globe.a + lid.r*back)
                    base[off+1] = u8(globe.g*globe.a + lid.g*back)
                    base[off+2] = u8(globe.b*globe.a + lid.b*back)
                    base[off+3] = u8(alpha)
                }
                spans[row] = start < end ? Span(start: start, end: end) : Span(start: 0, end: 0)
            }
        }
        return Prepared(spec: spec, bounds: (b.minX,b.minY,b.maxX,b.maxY), width: width, height: height, base: base, spans: spans)
    }

    public static func render(spec: VectorEyeSpec, pose: SphericalEyePose) -> Buffer {
        if spec == .left { return render(prepared: leftPrepared, pose: pose) }
        if spec == .right { return render(prepared: rightPrepared, pose: pose) }
        // No unbounded cache keyed by arbitrary specs/poses.
        return render(prepared: prepare(spec: spec), pose: pose)
    }

    public static func render(prepared: Prepared, pose: SphericalEyePose) -> Buffer {
        let spec = prepared.spec, width = prepared.width, height = prepared.height
        let b = prepared.bounds, e = spec.sclera
        var rgba = prepared.base // COW: independent output on first write.
        let edge = 1.6 / min(e.radiusX, e.radiusY)
        for row in 0..<height {
            let span = prepared.spans[row]
            if span.start == span.end { continue }
            // Preserve pixel centers, original arithmetic and top-down rows.
            let y = b.1 + Double(row) + 0.5
            let unitY = (y-e.center.y)/e.radiusY
            let rowOff = row*width*4
            for col in span.start..<span.end {
                let x = b.0 + Double(col) + 0.5
                let unitX = (x-e.center.x)/e.radiusX
                let globe = SphereShade.sample(unitX: unitX, unitY: unitY, dir: pose.direction,
                    irisAlpha: pose.irisAngularRadius, pupilAlpha: pose.pupilAngularRadius, edgeWidth: edge)
                let lid = globe.a < 1 ? EyeLidShade.sample(x: x, y: y, spec: spec) : .transparent
                let a = globe.a + lid.a * (1-globe.a)
                if a <= 0 { continue }
                let back = lid.a * (1-globe.a), off = rowOff+col*4
                rgba[off+0] = u8(globe.r*globe.a + lid.r*back)
                rgba[off+1] = u8(globe.g*globe.a + lid.g*back)
                rgba[off+2] = u8(globe.b*globe.a + lid.b*back)
                rgba[off+3] = u8(a)
            }
        }
        return Buffer(minX: b.0, minY: b.1, width: width, height: height, rgba: rgba)
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

/// Dark-iris / pupil centroid in canvas pixels (y-down), relative to the *sclera*
/// (the globe), not the lid shell. Used so PNG measurements are never trusted
/// only from pose JSON vectors.
public enum SphereImageMeasure {
    public struct Result: Equatable, Sendable {
        public var canvasX: Double
        public var canvasY: Double
        public var unitX: Double
        public var unitY: Double
        public var samples: Int

        public var isBelowCenter: Bool { unitY > 0 }
        public var isAboveCenter: Bool { unitY < 0 }
        public var isRightOfCenter: Bool { unitX > 0 }
        public var isLeftOfCenter: Bool { unitX < 0 }
    }

    /// `sample` returns un-premultiplied 0…255 RGBA at integer canvas pixels,
    /// or nil if outside the image.
    public static func darkIrisCentroid(
        sclera: AxisAlignedEllipse,
        sample: (_ canvasX: Int, _ canvasY: Int) -> (r: Int, g: Int, b: Int, a: Int)?
    ) -> Result? {
        let x0 = Int(floor(sclera.minX))
        let y0 = Int(floor(sclera.minY))
        let x1 = Int(ceil(sclera.maxX))
        let y1 = Int(ceil(sclera.maxY))
        var sx = 0.0, sy = 0.0, sw = 0.0
        var n = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let ux = (Double(x) - sclera.center.x) / sclera.radiusX
                let uy = (Double(y) - sclera.center.y) / sclera.radiusY
                if ux * ux + uy * uy >= 0.97 { continue }
                guard let p = sample(x, y), p.a >= 200 else { continue }
                let bright = Double(p.r + p.g + p.b) / 3
                let chroma = Double(max(p.r, p.g, p.b) - min(p.r, p.g, p.b))
                let pupil = p.r < 48 && p.g < 38 && p.b < 32
                let iris = bright < 145 && chroma > 22 && p.r > p.g && p.g + 8 >= p.b
                if !pupil && !iris { continue }
                let w = pupil ? 4.0 : 1.0
                sx += Double(x) * w
                sy += Double(y) * w
                sw += w
                n += 1
            }
        }
        guard sw > 40, n > 40 else { return nil }
        let cx = sx / sw
        let cy = sy / sw
        return Result(
            canvasX: cx,
            canvasY: cy,
            unitX: (cx - sclera.center.x) / sclera.radiusX,
            unitY: (cy - sclera.center.y) / sclera.radiusY,
            samples: n
        )
    }

    public static func darkIrisCentroid(buffer: SphereRasterBuffer.Buffer, sclera: AxisAlignedEllipse) -> Result? {
        darkIrisCentroid(sclera: sclera) { x, y in
            SphereRasterBuffer.pixel(in: buffer, canvasX: x, canvasY: y)
        }
    }

    /// Same sign, with a dead zone so near-axis values are not forced.
    public static func sameDirection(_ a: Double, _ b: Double, epsilon: Double = 0.03) -> Bool {
        if abs(a) < epsilon || abs(b) < epsilon { return abs(a) < epsilon || a * b >= 0 }
        return a * b > 0
    }
}
