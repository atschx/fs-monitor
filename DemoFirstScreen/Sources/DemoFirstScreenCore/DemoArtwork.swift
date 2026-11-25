import Foundation

/// URLs for the documented D2 crops bundled next to the production snapshot.
/// Core stays Foundation-only; the App target loads NSImage from these URLs.
public enum DemoArtwork {
    public static func url(named name: String) -> URL? {
        let png = name.hasSuffix(".png") ? name : "\(name).png"
        let stem = png.hasSuffix(".png") ? String(png.dropLast(4)) : name
        return ModuleBundle.url(named: ModuleBundle.coreName, resource: png, ext: nil, subdirectories: ["Resources/artwork", "artwork", nil])
            ?? ModuleBundle.url(named: ModuleBundle.coreName, resource: stem, ext: "png", subdirectories: ["Resources/artwork", "artwork", nil])
    }
}
