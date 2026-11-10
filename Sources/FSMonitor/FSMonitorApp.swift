#if os(macOS)
import SwiftUI

@main
struct FSMonitorApp: App {
    @StateObject private var controller = MonitorController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
        // Huluwa board recommends ~1368×872 as a default canvas, not a hard minimum.
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
#endif
