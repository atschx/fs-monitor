#if os(macOS)
import AppKit
import SwiftUI
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

/// At most one pending main-queue progress delivery, latest count wins.
private final class FolderCountMailbox {
    private let lock=NSLock();private var pending=false,latest=0
    private let deliver:(Int)->Void
    init(_ deliver:@escaping(Int)->Void){self.deliver=deliver}
    func put(_ n:Int){lock.lock();latest=n;let enqueue = !pending;pending=true;lock.unlock();guard enqueue else{return}
        DispatchQueue.main.async{self.lock.lock();let n=self.latest;self.pending=false;self.lock.unlock();self.deliver(n)}
    }
}
/// App-layer only. Init/body/launch never select a URL, show a panel, or scan.
final class FolderSnapshotStore:ObservableObject {
    @Published private(set) var state=FolderReadState()
    private var cancellation:ScanCancellation?
    private let worker=DispatchQueue(label:"local.fsmonitor.explicit-one-shot",qos:.utility)
    private(set) var scansStarted=0
    init(state:FolderReadState=FolderReadState()){self.state=state}
    func chooseFolder(){
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.canCreateDirectories=false;panel.allowsMultipleSelection=false;panel.resolvesAliases=true
        panel.prompt="选择文件夹并读取";panel.message="只读取你选择的文件夹一次；不自动监控、不保存结果。子符号链接和其他挂载点不进入。"
        panel.begin{[weak self] response in
            guard response == .OK,let url=panel.url else{return}
            // URL is the user's exact panel result, never HOME/default programmatic selection.
            guard let self else{url.stopAccessingSecurityScopedResource();return}
            self.readSelectedPanelURL(url)
        }
    }
    private func readSelectedPanelURL(_ url:URL){
        cancellation?.cancel();let token=ScanCancellation();cancellation=token
        let root=url.standardizedFileURL.path,generation=state.begin(root:url.standardizedFileURL.path)
        scansStarted+=1
        // Apple: standard Open Panel URLs already carry an implicit session scope.
        // Do not double-start it. Always revoke that lease AFTER work actually ends,
        // including cancellation/late results. False explicit start is not an I/O error.
        let lease=SessionScopeLease(implicitPanelAccess:true,start:{url.startAccessingSecurityScopedResource()},stop:{url.stopAccessingSecurityScopedResource()})
        worker.async{[weak self] in
            defer{lease.close()}
            let mailbox=FolderCountMailbox{[weak self] n in self?.state.progress(n,generation:generation,root:root)}
            let scan=DirectoryScanner.scan(root:url,cancellation:token,progressStride:100){progress in mailbox.put(progress.visited)}
            let result=FolderAdapter.adapt(scan)
            DispatchQueue.main.async{[weak self] in _=self?.state.finish(result,generation:generation,root:root)}
        }
    }
    func cancel(){cancellation?.cancel();state.cancel()}
    deinit{cancellation?.cancel()}
}

struct FolderSnapshotRootView:View {
    @ObservedObject var store:FolderSnapshotStore
    @ObservedObject var eyes:EyeFrameDriver
    var renderPart:DemoRenderPart = .normal
    var body:some View {
        GeometryReader{geo in
            let map=WindowCanvasMap(width:geo.size.width,height:geo.size.height)
            ZStack(alignment:.topLeading){
                DemoRootView(snapshot:store.state.snapshot,eyeFrames:eyes,renderPart:renderPart).id(store.state.revision)
                    .onChange(of:store.state.revision){_ in
                        let frame=FramePresentation.make(session:InteractionSession(snapshot:store.state.snapshot),motion:.defaultMotion,pointerInsideWindow:false)
                        eyes.gpu?.snapshotSourceChanged(frame.eye.resolvedTarget,reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                    }
                FolderReadControls(state:store.state,choose:{store.chooseFolder()},cancel:{store.cancel()})
                    .frame(width:430,alignment:.leading).scaleEffect(map.scale,anchor:.topLeading)
                    .offset(x:map.origin.x+68*map.scale,y:map.origin.y+405*map.scale)
            }
        }
    }
}
struct FolderReadControls:View {
    let state:FolderReadState
    var choose:()->Void = {},cancel:()->Void = {}
    private var time:String {
        guard let d=state.visible?.snapshot.endedAt else{return ""}
        let f=DateFormatter();f.timeZone=TimeZone(identifier:"America/Los_Angeles");f.dateFormat="HH:mm:ss 'PST'";return f.string(from:d)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Button("选择文件夹并读取",action:choose).buttonStyle(.borderedProminent)
            if state.reading {Button("取消读取",action:cancel)}
            Text(state.root.map{URL(fileURLWithPath:$0).lastPathComponent} ?? "未选择范围").fontWeight(.semibold)
            Text(state.status)
            Text("logical st_size · 十进制 GB")
            Text("只读一次，不监控、不跨启动保存")
            if state.visible != nil {Text((state.stale ? "旧值 · ":"快照 · ")+time)}
            if let result=state.visible {
                if !ChartabilityGate.evaluate(result.snapshot).isChartable {
                    ForEach(result.snapshot.items,id:\.id){item in
                        Text(item.name+" · "+FolderAdapter.bytesText(item.knownBytes ?? 0)+(result.isComplete ? "":" 已读下界；完整未知"))
                    }
                }
                if !result.isComplete {Text("部分/失败不画比例；未知不是0")}
                if let issue=result.issues.first {Text(issue).lineLimit(3)}
            }
        }
        .font(.system(size:25)).foregroundColor(Color(red:0.20,green:0.36,blue:0.37))
        .padding(16).background(RoundedRectangle(cornerRadius:16).fill(Color(red:1,green:0.98,blue:0.94).opacity(0.94)))
        .accessibilityElement(children:.contain)
    }
}
#endif
