#if !os(macOS)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

@main
struct FSMonitorLinuxStub {
    static func main() {
        let message = """
        FSMonitor 的界面是 macOS 应用，当前系统不能启动它。
        可移植核心的测试命令：swift test
        这不是 macOS 构建。
        """
        fputs(message + "\n", stderr)
        exit(2)
    }
}
#endif
