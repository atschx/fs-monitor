#if !os(macOS)
import Foundation

@main
enum DemoFirstScreenUnsupported {
    static func main() {
        fputs("DemoFirstScreen targets native macOS 13+ / Apple Silicon and cannot run on this platform.\n", stderr)
        exit(1)
    }
}
#endif
