#if os(macOS)
import AppKit
import CoreGraphics
import DemoFirstScreenCore

/// CPU raster of one globe into a CGImage, using `SphereShade` on the documented
/// sclera ellipse. CoreGraphics and NSImage are public on macOS 13. SceneKit
/// (also public on 13) was considered but not used, so the globe stays on the
/// existing ellipse placement and the shader can be unit-tested in Core.
///
/// The buffer is top-down (row 0 = canvas `minY`). 074605 inverted this and
/// the cacheDisplay PNGs came out Y-flipped relative to the pose JSON.
enum SphereEyeRaster {
    static func nsImage(spec: VectorEyeSpec, pose: SphericalEyePose) -> NSImage? {
        let buffer = SphereRasterBuffer.render(spec: spec, pose: pose)
        return nsImage(buffer: buffer)
    }

    static func nsImage(buffer: SphereRasterBuffer.Buffer) -> NSImage? {
        guard buffer.width > 2, buffer.height > 2 else { return nil }

        return buffer.rgba.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            // Copy: CGContext may assume unique ownership of the pointer.
            let count = buffer.rgba.count
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            bytes.initialize(from: base.assumingMemoryBound(to: UInt8.self), count: count)
            defer { bytes.deallocate() }
            guard let ctx = CGContext(
                data: bytes,
                width: buffer.width,
                height: buffer.height,
                bitsPerComponent: 8,
                bytesPerRow: buffer.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ), let image = ctx.makeImage() else {
                return nil
            }
            return NSImage(cgImage: image, size: NSSize(width: buffer.width, height: buffer.height))
        }
    }

    /// Canvas-space rectangle covered by the raster (including 1 px pad).
    static func canvasRect(spec: VectorEyeSpec) -> CGRect {
        let b = SphereRasterBuffer.canvasBounds(spec: spec)
        return CGRect(x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY)
    }
}
#endif
