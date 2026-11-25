import Foundation

/// Locates a SwiftPM resource bundle without the generated `Bundle.module`
/// initializer. That initializer traps when the bundle is absent or is only a
/// symbolic link the bundle loader does not accept.
public enum ModuleBundle {
    public static let coreName = "DemoFirstScreen_DemoFirstScreenCore"
    public static let appName = "DemoFirstScreen_DemoFirstScreenApp"

    public static func bundle(named name: String) -> Bundle? {
        var seen = Set<String>()
        for base in searchBases() {
            let key = base.path
            if !seen.insert(key).inserted { continue }
            if let bundle = open(base.appendingPathComponent(name + ".bundle", isDirectory: true)) {
                return bundle
            }
        }
        return nil
    }

    public static func url(named name: String, resource: String, ext: String?, subdirectories: [String?]) -> URL? {
        if let bundle = bundle(named: name) {
            for subdirectory in subdirectories {
                if let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: subdirectory) {
                    return url
                }
            }
        }
        let filename = ext.map { resource + "." + $0 } ?? resource
        let fm = FileManager.default
        for base in searchBases() {
            let root = base.appendingPathComponent(name + ".bundle", isDirectory: true)
            let resolved = root.resolvingSymlinksInPath()
            for subdirectory in subdirectories {
                let relative = subdirectory.map { $0 + "/" + filename } ?? filename
                for prefix in ["", "Contents/Resources/", "Resources/"] {
                    for bundleRoot in [root, resolved] {
                        let url = bundleRoot.appendingPathComponent(prefix + relative)
                        if fm.fileExists(atPath: url.path) { return url }
                    }
                }
            }
        }
        return nil
    }

    private static func open(_ url: URL) -> Bundle? {
        if let bundle = Bundle(url: url) { return bundle }
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path != url.path else { return nil }
        return Bundle(url: resolved)
    }

    private static func searchBases() -> [URL] {
        var urls: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            urls.append(url)
        }
        let bundles = Bundle.allBundles + [Bundle.main]
        for bundle in bundles {
            add(bundle.resourceURL)
            add(bundle.executableURL?.deletingLastPathComponent())
            add(bundle.bundleURL)
            add(bundle.bundleURL.deletingLastPathComponent())
            add(bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
            add(bundle.bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true))
        }
        return urls
    }
}
