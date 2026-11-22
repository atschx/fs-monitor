#if os(macOS)
import SwiftUI
struct IntegratedMetalLayer:NSViewRepresentable {
    let gpu:IntegratedGPUEyes
    func makeNSView(context:Context)->EyeMetalView{gpu.view}
    func updateNSView(_ view:EyeMetalView,context:Context){}
}
#endif
