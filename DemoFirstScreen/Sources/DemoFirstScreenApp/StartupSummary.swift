#if os(macOS)
import AppKit
import SwiftUI
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

private final class MetadataReadBox:@unchecked Sendable {
    let lock=NSLock();var bytes=Data()
}
enum StartupMetadata {
    /// Public, read-only OS metadata tool. No shell, private TCC database,
    /// user directory listing, mounts, or disk mutations. Never log raw plist.
    static func plist(_ args:[String],cancel:ScanCancellation)throws->[String:Any] {
        guard !cancel.isCancelled else{throw StartupMappingError.cancelled}
        let process=Process(),pipe=Pipe(),box=MetadataReadBox(),done=DispatchSemaphore(value:0)
        process.executableURL=URL(fileURLWithPath:"/usr/sbin/diskutil");process.arguments=args
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        try process.run()
        DispatchQueue.global(qos:.utility).async {let data=pipe.fileHandleForReading.readDataToEndOfFile();box.lock.lock();box.bytes=data;box.lock.unlock();done.signal()}
        guard done.wait(timeout:.now()+8) == .success else {if process.isRunning{process.terminate()};throw StartupMappingError.metadataUnavailable}
        process.waitUntilExit();guard process.terminationStatus==0,!cancel.isCancelled else{throw StartupMappingError.metadataUnavailable}
        box.lock.lock();let data=box.bytes;box.lock.unlock()
        guard data.count<4_000_000,let value=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else{throw StartupMappingError.metadataUnavailable};return value
    }
    static func mapping(cancel:ScanCancellation)throws->StartupDataProof {
        let root=try plist(["info","-plist","/"],cancel:cancel)
        guard let container=root["APFSContainerReference"] as? String,StartupDataMapping.validDevice(container) else{throw StartupMappingError.unsupported}
        let data=try plist(["info","-plist",StartupDataMapping.dataPath],cancel:cancel)
        let groups=try plist(["apfs","listVolumeGroups","-plist",container],cancel:cancel)
        let system=try StartupDataMapping.systemMember(root:root,groups:groups)
        let snapshots=try plist(["apfs","listSnapshots","-plist",system],cancel:cancel)
        return try StartupDataMapping.verify(root:root,data:data,groups:groups,snapshots:snapshots)
    }
    static func displayedCapacity(_ proof:StartupDataProof)->(Int64?,Int64?) {
        // Only displayed locally; never serialized into diagnostics/archives.
        let v=try? URL(fileURLWithPath:proof.dataPath).resourceValues(forKeys:[.volumeTotalCapacityKey,.volumeAvailableCapacityKey])
        return (v?.volumeTotalCapacity.map(Int64.init),v?.volumeAvailableCapacity.map(Int64.init))
    }
}
/// One coalesced main delivery for potentially frequent scan updates.
private final class SummaryMailbox {
    private let lock=NSLock();private var pending=false,latest=ScanCandidates(visited:0,logicalByTop:[:])
    let deliver:(ScanCandidates)->Void
    init(_ f:@escaping(ScanCandidates)->Void){deliver=f}
    func put(_ value:ScanCandidates){lock.lock();latest=value;let send = !pending;pending=true;lock.unlock();guard send else{return}
        DispatchQueue.main.async{self.lock.lock();let v=self.latest;self.pending=false;self.lock.unlock();self.deliver(v)}
    }
}
final class StartupSummaryStore:ObservableObject {
    @Published private(set) var state=FolderReadState()
    @Published private(set) var consent=StartupConsent()
    @Published private(set) var message="尚未读取本机目录。先了解范围，再明确开始授权概览。"
    @Published private(set) var candidates=[SnapshotItem]()
    @Published private(set) var capacity:Int64?,available:Int64?
    @Published private(set) var phase="neutral"
    private var observers=[NSObjectProtocol]()
    private var cancellation:ScanCancellation?
    private let worker=DispatchQueue(label:"local.fsmonitor.user-consented-startup-once",qos:.utility)
    private(set) var scansStarted=0
    init(){
        let c=NotificationCenter.default
        observers.append(c.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main){[weak self]_ in self?.consent.resigned()})
        observers.append(c.addObserver(forName:NSApplication.didBecomeActiveNotification,object:NSApp,queue:.main){[weak self]_ in guard let self else{return};if self.consent.returned(){self.beginAttempt()}})
    }
    deinit{cancellation?.cancel();for x in observers{NotificationCenter.default.removeObserver(x)}}
    var displaySnapshot:DemoSnapshot {phase=="complete" ? state.snapshot:FolderAdapter.neutral(label:"启动盘数据概览")}
    func requestAuthorization(){
        cancel();consent.request();phase="authorization"
        message="请在系统设置→隐私与安全性→完全磁盘访问中允许这个App。返回后仅尝试一次；返回不代表授权成功。若系统要求重启，请本人处理后重新开始。"
        if let settings=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences"){NSWorkspace.shared.open(settings)}
    }
    func continueOnce(){if consent.manualContinue(){beginAttempt()}}
    func cancel(){consent.cancel();cancellation?.cancel();state.cancel();phase="cancelled";candidates=[];message="已取消；完整范围未知，不画比例。未开启监控。"}
    private func beginAttempt(){
        let token=ScanCancellation();cancellation=token;phase="mapping";candidates=[]
        let root=StartupDataMapping.dataPath,generation=state.begin(root:StartupDataMapping.dataPath)
        message="核对启动盘System/Data卷组与启动快照；FDA状态未知，按实际访问结果显示。"
        worker.async{[weak self] in
            do {
                let proof=try StartupMetadata.mapping(cancel:token)
                guard !token.isCancelled else{return}
                let volume=StartupMetadata.displayedCapacity(proof)
                DispatchQueue.main.async{[weak self] in guard let self,self.state.generation==generation,self.state.reading else{return};self.capacity=volume.0;self.available=volume.1;self.phase="reading";self.message="已核System/Data关联；只读Data命名空间一次。下列仅已读最大候选，完整量未知。";self.scansStarted+=1}
                guard !token.isCancelled else{return}
                let mailbox=SummaryMailbox{[weak self] value in guard let self,self.state.generation==generation,self.state.reading else{return};self.state.progress(value.visited,generation:generation,root:root);self.candidates=FolderAdapter.candidateItems(value.logicalByTop)}
                let scan=DirectoryScanner.scan(root:URL(fileURLWithPath:proof.dataPath),cancellation:token,progressStride:500,candidates:{mailbox.put($0)})
                let result=FolderAdapter.adapt(scan)
                DispatchQueue.main.async{[weak self] in
                    guard let self,self.state.finish(result,generation:generation,root:root) else{return}
                    self.candidates=result.snapshot.items
                    switch result.outcome {
                    case .complete:self.phase="complete";self.message="本次完整可加总logical范围；比例分母仅已枚举Data文件logical合计，不是全盘物理占用。"
                    case .empty:self.phase="empty";self.message="读取成功：本次可计logical为0；不是整盘空闲/占用。"
                    case .partial:self.phase="partial";self.message="部分读取：已读最大候选，完整总量未知，不画全盘确定比例。FDA也不能绕过其他权限。"
                    case .failed:self.phase="failed";self.message="读取失败/权限不足：总量未知，不是0；请本人检查FDA。"
                    case .cancelled:self.phase="cancelled";self.message="已取消：完整总量未知。"
                    }
                }
            }catch {
                DispatchQueue.main.async{[weak self] in guard let self,self.state.generation==generation,self.state.reading else{return};self.state.cancel();self.phase="unsupported";self.message="未能证实标准启动盘System/Data关联，或元数据不可用；未开始目录遍历。不退回HOME或/。"}
            }
        }
    }
    /// Evidence-only injection: no metadata query, permission request or scan.
    func injectEvidence(state:FolderReadState,phase:String,message:String,candidates:[SnapshotItem]=[]){self.state=state;self.phase=phase;self.message=message;self.candidates=candidates;self.capacity=1_000_000_000_000;self.available=128_000_000_000;if phase=="authorization" {consent.request()}}
}
struct StartupSummaryRootView:View {
    @ObservedObject var store:StartupSummaryStore
    @ObservedObject var eyes:EyeFrameDriver
    var renderPart:DemoRenderPart = .normal
    var evidenceSession:InteractionSession? = nil
    var body:some View {
        GeometryReader{geo in
            let map=WindowCanvasMap(width:geo.size.width,height:geo.size.height)
            ZStack(alignment:.topLeading){
                DemoRootView(snapshot:store.displaySnapshot,session:evidenceSession,eyeFrames:eyes,renderPart:renderPart).id(store.state.revision)
                StartupSummaryControls(store:store).frame(width:430,alignment:.leading).scaleEffect(map.scale,anchor:.topLeading)
                    .offset(x:map.origin.x+68*map.scale,y:map.origin.y+405*map.scale)
            }
        }.onChange(of:store.phase){_ in
            let frame=FramePresentation.make(session:InteractionSession(snapshot:store.displaySnapshot),motion:.defaultMotion,pointerInsideWindow:false)
            eyes.gpu?.snapshotSourceChanged(frame.eye.resolvedTarget,reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }
}
struct StartupSummaryControls:View {
    @ObservedObject var store:StartupSummaryStore
    func number(_ n:Int64?)->String {n.map{String(format:"%.2f GB",Double($0)/1_000_000_000)} ?? "未知"}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Button("开始授权启动盘概览"){store.requestAuthorization()}.buttonStyle(.borderedProminent).disabled(store.state.reading)
            Text("启动盘用户与应用数据 · 只读一次，可取消")
            Text("仅已核Data；不同时扫/；不跟随符号链接或跨挂载。不是仅HOME。")
            Text(store.message).lineLimit(store.phase=="authorization" ? nil:3)
            if store.consent.armed {Button("已处理授权，尝试一次"){store.continueOnce()}}
            if store.consent.armed || store.state.reading {Button("取消本次概览"){store.cancel()}}
            if store.capacity != nil || store.available != nil {
                Text("Data卷容量："+number(store.capacity)+"；可用："+number(store.available))
                Text("APFS空间可能共享；卷容量与下列文件logical不是同一口径。")
            }
            if store.state.reading {Text("已访问\(store.state.visited)项 · 无虚构百分比")}
            if store.phase != "complete",!store.candidates.isEmpty {
                Text("已读最大候选 · logical，非确定全盘排名").fontWeight(.semibold)
                ForEach(store.candidates,id:\.id){item in Text(item.name+" · "+FolderAdapter.bytesText(item.knownBytes ?? 0))}
            }
            if store.phase=="complete" {Text("logical分母："+FolderAdapter.bytesText(store.state.snapshot.folderLogicalProof?.bucketTotal ?? 0)+"；仅同源可加总范围")}
            Text("不监控，不保存结果，不上传路径或清单。")
        }.font(.system(size:24)).foregroundColor(Color(red:0.20,green:0.36,blue:0.37))
            .padding(16).background(RoundedRectangle(cornerRadius:16).fill(Color(red:1,green:0.98,blue:0.94).opacity(0.94)))
    }
}
#endif
