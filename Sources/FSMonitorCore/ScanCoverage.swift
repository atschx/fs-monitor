import Foundation

/// Interprets scan issues that mean a path was not fully observed, so absence
/// must not be treated as a confident add/remove.
public enum ScanCoverage: Sendable {
    /// Returns true when `issues` show that `relativePath` may be missing from
    /// `entriesByPath` because of a coverage gap rather than a real filesystem change.
    public static func preventsConfidentAbsence(
        of relativePath: String,
        issues: [ScanIssue]
    ) -> Bool {
        let path = normalize(relativePath)
        guard !path.isEmpty else { return false }
        for issue in issues {
            let issuePath = normalize(issue.path)
            let message = issue.message
            // Status read failure on a path also means nothing under it was observed
            // (directory lstat fail never descends). Exact-only matching would still
            // mark baseline descendants as confident deletes.
            if isUnreadStatus(message) && covers(issuePath, descendantOrSelf: path) {
                return true
            }
            if isDirectoryListFailure(message) && covers(issuePath, descendantOrSelf: path) {
                return true
            }
            if isMountPointSkipped(message) && isStrictAncestor(issuePath, of: path) {
                return true
            }
        }
        return false
    }

    public static func normalize(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") {
            value = String(value.dropFirst(2))
        }
        if value.hasSuffix("/"), value.count > 1 {
            value.removeLast()
        }
        if value.isEmpty {
            return "."
        }
        return value
    }

    private static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    private static func isStrictAncestor(_ ancestor: String, of descendant: String) -> Bool {
        let parent = normalize(ancestor)
        let child = normalize(descendant)
        if parent == "." {
            return child != "."
        }
        return child.hasPrefix(parent + "/")
    }

    private static func covers(_ issuePath: String, descendantOrSelf path: String) -> Bool {
        let parent = normalize(issuePath)
        let child = normalize(path)
        if parent == "." {
            return true
        }
        return pathsEqual(parent, child) || child.hasPrefix(parent + "/")
    }

    private static func isUnreadStatus(_ message: String) -> Bool {
        message.contains("无法读取文件状态")
    }

    private static func isDirectoryListFailure(_ message: String) -> Bool {
        message.contains("无法列出目录")
    }

    private static func isMountPointSkipped(_ message: String) -> Bool {
        message.contains("其他挂载点") && message.contains("未进入")
    }
}
