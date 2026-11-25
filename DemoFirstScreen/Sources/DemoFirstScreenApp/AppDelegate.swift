#if os(macOS)
import AppKit
import SwiftUI
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

private enum StartupFailure {
    static func exit(_ message: String) -> Never {
        fputs("Startup resources unavailable: \(message)\n", stderr)
        fflush(stderr)
        Darwin.exit(1)
    }
}

@main
enum DemoFirstScreenMain {
    static func main() {
        let app = NSApplication.shared
        let args=CommandLine.arguments
        if args.contains("--startup-metadata-verify-only") {
            do { _=try StartupMetadata.mapping(cancel:ReadOnlyScanner.ScanCancellation());print("{\"verifiedStandardAPFSAssociation\":true,\"bootSnapshotSystemDataRolesChecked\":true,\"directoryTraversal\":false,\"FDAProven\":false,\"privateIdentifiersExported\":false}") }
            catch {fputs("Startup System/Data mapping could not be proven; no traversal\n",stderr);exit(1)}
            return
        }
        if let i=args.firstIndex(of:"--gpu-verify-only"),i+1<args.count {
            app.setActivationPolicy(.prohibited)
            do {
                let directory=URL(fileURLWithPath:args[i+1],isDirectory:true)
                guard !FileManager.default.fileExists(atPath:directory.path) else{throw StudyFailure("Refuse existing GPU verification output")}
                let backend=try MetalBackend()
                try runVerification(backend,to:directory)
                try LocalEventSelfCheck.run(to:directory.appendingPathComponent("local-event-synthetic-selfcheck.json"))
                try SafetyEvidence.write(backend:backend,example:SnapshotLoader.loadBundledExampleInteraction(),to:directory.appendingPathComponent("safe-gaze"))
                try StartupSummaryEvidence.write(backend:backend,to:directory.appendingPathComponent("startup-summary"))
                try GPUIntegrationEvidence.write(example:SnapshotLoader.loadBundledExampleInteraction(),backend:backend,to:directory.appendingPathComponent("full-demo"))
            }catch{fputs("GPU integration verification failed (no fallback): \(error)\n",stderr);exit(1)}
            return
        }
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var retained: AppDelegate?
    private var window: NSWindow?
    /// Real Eric du snapshot is loaded and retained, but never used for area / angles.
    private var retainedProduction: DemoSnapshot?
    private var summaryStore:StartupSummaryStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Explicit example is verification-only. Default opens neutral; no scanner/panel.
        let example=FolderAdapter.neutral()
        guard let hubURL = DemoArtwork.url(named: "d2-hub"), let restURL = DemoArtwork.url(named: "d2-eyes-rest") else {
            StartupFailure.exit("Required startup artwork is not in the app resource bundle.")
        }

        let initial = FramePresentation.make(session: InteractionSession(snapshot: example), motion: .reduced, pointerInsideWindow: false)
        let gpu:IntegratedGPUEyes
        do {
            let args=CommandLine.arguments
            let i=args.firstIndex(of:"--integrated-gpu-diagnostics-dir")
            let out=i.flatMap{$0+1<args.count ? URL(fileURLWithPath:args[$0+1],isDirectory:true):nil}
            gpu=try IntegratedGPUEyes(backend:MetalBackend(),diagnostics:out,runIdleTrial:args.contains("--safe-idle-finite-trial"),startingTarget:initial.eye.resolvedTarget)
        }catch{StartupFailure.exit("GPU backend unavailable; CPU reference not substituted: \(error)")}
        let eyes = EyeFrameDriver(target: initial.eye.resolvedTarget,gpu:gpu)
        let store=StartupSummaryStore();self.summaryStore=store
        precondition(store.scansStarted==0 && store.state.root==nil && !store.state.reading)
        if CommandLine.arguments.contains("--integrated-gpu-diagnostics-dir") {
            fputs("summary-startup: scansStarted=0 root=nil reading=false panel=not-requested\n",stdout);fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline:.now()+3){[weak store] in
                if let store {fputs("summary-startup-after3s: scansStarted=\(store.scansStarted) rootSelected=\(store.state.root != nil) reading=\(store.state.reading)\n",stdout);fflush(stdout)}
            }
        }
        let root = StartupSummaryRootView(store:store,eyes:eyes)
        let host = ClearHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor

        // Truly borderless and transparent: no titlebar chrome, no traffic-light
        // buttons, no opaque window fill. Public AppKit only. The system menu
        // bar is not hidden (not a system-setting change).
        let window = BorderlessDemoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.acceptsMouseMovedEvents = true
        window.contentView = host
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.center()
        installMinimalMenu()
        self.window = window
        gpu.observeLifecycle(window:window)
        // First live image is prepared off-main before showing the window;
        // never present empty eyes or synchronously rasterize on pointer input.
        eyes.onFirstFrame = { [weak window] in
            window?.makeKeyAndOrderFront(nil)
            window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            if let content=window?.contentView {Self.recordOwnCatcherGeometry(content)}
            Self.writeStartupReceipt(hub: hubURL, rest: restURL, scansStarted: store.scansStarted)
        }
        eyes.start()

        if let dir = Self.evidenceDirectory(), !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            do {
                try DemoEvidence.writeWindowProperties(window, to: url)
                if CommandLine.arguments.contains("--minimal-performance-evidence") {
                    try DemoEvidence.writeMinimalPerformanceEvidence(example: example, to: url)
                } else {
                    try DemoEvidence.writeOffscreenFrames(example: example, to: url)
                    DemoEvidence.writeClockDrivenGazeEvidence(example: example, to: url)
                }
            } catch {
                FileManager.default.createFile(
                    atPath: url.appendingPathComponent("evidence-error.txt").path,
                    contents: String(describing: error).data(using: .utf8)
                )
            }
        }
    }

    private static func recordOwnCatcherGeometry(_ view:NSView){
        if let catcher=view as? EventCatcher.CatcherView {catcher.recordGeometry(reason:"actual-live-window-shown")}
        for child in view.subviews {recordOwnCatcherGeometry(child)}
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Keyboard close/quit only. This is not window chrome and adds no buttons.
    private func installMinimalMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DemoFirstScreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(AppDelegate.closeDemoWindow), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.mainMenu = menu
    }

    @objc private func closeDemoWindow() {
        window?.close()
    }

    private static func writeStartupReceipt(hub: URL, rest: URL, scansStarted: Int) {
        guard let path = ProcessInfo.processInfo.environment["FS_MONITOR_STARTUP_RECEIPT"], !path.isEmpty else { return }
        let metal = ModuleBundle.url(named: ModuleBundle.appName, resource: "Eyes", ext: "metal", subdirectories: ["Resources", nil])
        func bytes(_ url: URL?) -> Int {
            guard let url, let data = try? Data(contentsOf: url) else { return -1 }
            return data.count
        }
        let body = "hub_bytes=\(bytes(hub))\nrest_bytes=\(bytes(rest))\nmetal_bytes=\(bytes(metal))\nwindow=ready\nscansStarted=\(scansStarted)\n"
        do {
            try body.write(toFile: path, atomically: true, encoding: .utf8)
            fputs("startup-receipt-written\n", stdout)
            fflush(stdout)
        } catch {
            StartupFailure.exit("could not record startup receipt")
        }
    }

    private static func evidenceDirectory() -> String? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--evidence-dir"), idx + 1 < args.count {
            return args[idx + 1]
        }
        let env = ProcessInfo.processInfo.environment["DEMO_FIRSTSCREEN_EVIDENCE_DIR"]
        if let env, !env.isEmpty { return env }
        return nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }
}
#endif
