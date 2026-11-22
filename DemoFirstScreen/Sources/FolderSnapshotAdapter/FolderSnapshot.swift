import Foundation
import DemoFirstScreenCore
import ReadOnlyScanner

public enum FolderBucketID:Equatable,Sendable {
    case directory(String),other
    public var encoded:String {switch self {case .directory(let path):return "directory:"+path;case .other:return "aggregate:other"}}
}
public enum FolderOutcome:String,Sendable {case complete,empty,partial,failed,cancelled}
public struct FolderResult:Sendable {
    public var root:String,outcome:FolderOutcome,snapshot:DemoSnapshot,visited:Int,issues:[String]
    public var isComplete:Bool {outcome == .complete || outcome == .empty}
}
public enum FolderAdapter {
    public static func neutral(label:String="未选择文件夹")->DemoSnapshot {
        let now=Date(timeIntervalSince1970:0)
        return DemoSnapshot(id:"folder:unselected",testOnly:false,label:label,startedAt:now,endedAt:now,timeZoneName:"America/Los_Angeles",caliber:.logical,caliberNote:"文件 logical st_size · 十进制 GB；非物理占用",apfsRootDataDedupVerified:false,nonOverlapVerified:false,activity:.notCollected,notes:[],items:[],folderLogicalProof:FolderLogicalProof(snapshotID:"folder:unselected",rootPath:"",complete:false,stableDeviceInodeOwnership:false,bucketTotal:0))
    }
    public static func stableBefore(_ a:String,_ b:String)->Bool {a.utf8.lexicographicallyPrecedes(b.utf8)}
    public static func adapt(_ scan:SpaceSnapshot,ended:Date=Date())->FolderResult {
        let id="folder:"+UUID().uuidString
        var issues=scan.issues.map{ $0.path+": "+$0.message }
        if let failure=scan.failureReason {issues.append(failure)}
        let ordered=scan.entriesByPath.values.sorted{stableBefore($0.relativePath,$1.relativePath)}
        let rootDevice=scan.entriesByPath["."]?.device
        var dirs=[String:Int64](),direct:Int64=0,seen=Set<String>(),sizes=[String:Int64]()
        func add(_ a:Int64,_ b:Int64)->Int64 {let (v,overflow)=a.addingReportingOverflow(b);if overflow || b<0 {issues.append("logical大小不可安全加总");return a};return v}
        for e in ordered where e.relativePath != "." {
            if !e.relativePath.contains("/"),e.kind == .directory {dirs[e.relativePath]=0}
        }
        // Ignore scanner's enumeration-time countsTowardTotal. Stable complete relative
        // path chooses device/inode ownership BEFORE aggregation or byte sorting.
        for e in ordered where e.relativePath != "." {
            guard e.device==rootDevice else{issues.append(e.relativePath+": 其他挂载点跳过");continue}
            if e.kind == .symbolicLink {issues.append(e.relativePath+": 符号链接未跟随，完整量未知");continue}
            guard e.kind == .regularFile else{continue}
            let inode="\(e.device):\(e.inode)"
            if let size=sizes[inode],size != e.logicalSize {issues.append(e.relativePath+": 同inode读取期间大小变化")}
            guard seen.insert(inode).inserted else{continue};sizes[inode]=e.logicalSize
            if let slash=e.relativePath.firstIndex(of:"/") {
                let top=String(e.relativePath[..<slash]);dirs[top]=add(dirs[top] ?? 0,e.logicalSize)
            } else {direct=add(direct,e.logicalSize)}
        }
        var sorted=dirs.map{(path:$0.key,bytes:$0.value)}.sorted{a,b in a.bytes==b.bytes ? stableBefore(a.path,b.path):a.bytes>b.bytes}
        let needsOther=direct>0 || sorted.count>5
        var other=direct
        if needsOther && sorted.count>4 {for x in sorted.dropFirst(4){other=add(other,x.bytes)};sorted=Array(sorted.prefix(4))}
        let partial = !scan.completed || scan.cancelled || !issues.isEmpty || rootDevice==nil
        let status:ReadStatus=partial ? .partial:.reportedComplete
        var items=sorted.map{SnapshotItem(id:FolderBucketID.directory($0.path).encoded,name:$0.path,bytes:$0.bytes,errorCount:partial ? max(1,issues.count):0,readStatus:status)}
        if other>0 {items.append(SnapshotItem(id:FolderBucketID.other.encoded,name:"其他项目",bytes:other,errorCount:partial ? max(1,issues.count):0,readStatus:status))}
        var total:Int64=0;for item in items{total=add(total,item.bytes ?? 0)}
        // Re-evaluate overflow appended while final total was accumulated.
        let complete = !partial && issues.isEmpty
        if !complete {for i in items.indices {items[i].readStatus = .partial;items[i].errorCount=max(1,issues.count)}}
        let outcome:FolderOutcome=scan.cancelled ? .cancelled : (rootDevice==nil || (!scan.completed && scan.failureReason != nil) ? .failed : (complete ? (total==0 ? .empty:.complete):.partial))
        let proof=FolderLogicalProof(snapshotID:id,rootPath:scan.rootPath,complete:complete,stableDeviceInodeOwnership:complete,bucketTotal:total)
        let snapshot=DemoSnapshot(id:id,testOnly:false,label:URL(fileURLWithPath:scan.selectedPath).lastPathComponent,startedAt:scan.capturedAt,endedAt:ended,timeZoneName:"America/Los_Angeles",caliber:.logical,caliberNote:"文件 logical st_size · 十进制 GB；按稳定路径唯一归属device/inode；非APFS物理块去重",apfsRootDataDedupVerified:false,nonOverlapVerified:complete,activity:.notCollected,notes:issues,items:items,folderLogicalProof:proof)
        return FolderResult(root:scan.selectedPath,outcome:outcome,snapshot:snapshot,visited:scan.entriesByPath.count,issues:issues)
    }
    public static func candidateItems(_ totals:[String:Int64])->[SnapshotItem] {
        var dirs=totals.filter{$0.key != "."}.map{(path:$0.key,bytes:$0.value)}.sorted{a,b in a.bytes==b.bytes ? stableBefore(a.path,b.path):a.bytes>b.bytes}
        var other=totals["."] ?? 0
        if other>0 || dirs.count>5 {for d in dirs.dropFirst(4) {let(v,overflow)=other.addingReportingOverflow(d.bytes);if !overflow{other=v}};dirs=Array(dirs.prefix(4))}
        var items=dirs.map{SnapshotItem(id:FolderBucketID.directory($0.path).encoded,name:$0.path,bytes:$0.bytes,errorCount:1,readStatus:.partial)}
        if other>0{items.append(SnapshotItem(id:FolderBucketID.other.encoded,name:"其他项目",bytes:other,errorCount:1,readStatus:.partial))};return items
    }
    public static func compactBytes(_ n:Int64)->String {n<1_000_000 ? "\(n) B" : String(format:"%.3f GB",Double(n)/1_000_000_000)}
    public static func bytesText(_ n:Int64)->String {
        if n<1_000_000_000{return "\(n) B（"+String(format:"%.6f",Double(n)/1_000_000_000)+" GB）"}
        return String(format:"%.3f GB",Double(n)/1_000_000_000)
    }
}

/// Pure root/generation reducer. No startup work, no filesystem/permission API.
public struct FolderReadState:Sendable {
    public private(set) var generation:UInt64=0,revision:UInt64=0
    public private(set) var root:String?,visible:FolderResult?,lastComplete:FolderResult?
    public private(set) var reading=false,stale=false,visited=0
    public private(set) var status="尚未读取；请自己选择范围"
    public init(){}
    @discardableResult public mutating func begin(root:String)->UInt64 {
        generation &+= 1;revision &+= 1;self.root=root;reading=true;visited=0
        visible=lastComplete?.root==root ? lastComplete:nil;stale=visible != nil
        status="读取中 · 已访问0项（无总数/百分比）";return generation
    }
    public mutating func progress(_ n:Int,generation:UInt64,root:String){guard self.generation==generation,self.root==root,reading else{return};visited=max(visited,n);status="读取中 · 已访问\(visited)项（无总数/百分比）"}
    @discardableResult public mutating func finish(_ result:FolderResult,generation:UInt64,root:String)->Bool {
        guard self.generation==generation,self.root==root,result.root==root,reading else{return false}
        reading=false;revision &+= 1;visited=result.visited
        if result.outcome == .cancelled {cancel();return true}
        visible=result;stale=false;if result.isComplete {lastComplete=result}
        switch result.outcome {case .complete:status="读取完成 · 一次快照，不自动监控";case .empty:status="读取成功：logical合计0 B（空或仅零大小文件）";case .partial:status="部分读取：仅列已读值，完整总量未知；不画比例";case .failed:status="读取失败：完整总量未知（不是0）";case .cancelled:break};return true
    }
    public mutating func cancel(){generation &+= 1;revision &+= 1;reading=false;visible=lastComplete?.root==root ? lastComplete:nil;stale=visible != nil;status=stale ? "已取消 · 显示同范围上次成功旧值与时间":"已取消 · 无完整结果，未知不补0"}
    public var snapshot:DemoSnapshot {visible?.snapshot ?? FolderAdapter.neutral()}
}

/// Balances either a panel's implicit lease or explicit successful start. False
/// start never means unreadable; caller still attempts ordinary filesystem access.
public final class SessionScopeLease {
    private var end:(()->Void)?
    public init(implicitPanelAccess:Bool,start:()->Bool,stop:@escaping()->Void){let acquired=implicitPanelAccess ? true:start();end=acquired ? stop:nil}
    public func close(){let f=end;end=nil;f?()}
    deinit{close()}
}
