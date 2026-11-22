import Foundation

/// URLs for the documented D2 crops bundled next to the production snapshot.
/// Core stays Foundation-only; the App target loads NSImage from these URLs.
public enum DemoArtwork {
    public static func url(named name: String) -> URL? {
        let bundle = Bundle.module
        let png = name.hasSuffix(".png") ? name : "\(name).png"
        return bundle.url(forResource: png, withExtension: nil, subdirectory: "Resources/artwork")
            ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources/artwork")
            ?? bundle.url(forResource: png, withExtension: nil, subdirectory: "artwork")
            ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "artwork")
            ?? bundle.url(forResource: png, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: "png")
    }
}
