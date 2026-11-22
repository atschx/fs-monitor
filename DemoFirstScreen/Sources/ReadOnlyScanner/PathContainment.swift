import Foundation

public enum PathContainment {
    public static func standardized(path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public static func isInside(rootPath: String, candidatePath: String) -> Bool {
        let root = standardized(path: rootPath)
        let candidate = standardized(path: candidatePath)
        if candidate == root {
            return true
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    /// 返回相对路径。根目录本身是 `"."`。不在根内时返回 nil。
    public static func relative(rootPath: String, candidatePath: String) -> String? {
        let root = standardized(path: rootPath)
        let candidate = standardized(path: candidatePath)
        if candidate == root {
            return "."
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate.hasPrefix(prefix) else { return nil }
        return String(candidate.dropFirst(prefix.count))
    }

    public static func breadthWarning(forRootPath path: String) -> String? {
        let standard = standardized(path: path)
        let components = URL(fileURLWithPath: standard).pathComponents
        guard components.count <= 2 else { return nil }
        return "这个目录范围很大。扫描可能很久，可以取消。应用不会删除其中的文件。"
    }
}
