import Foundation

public enum StartupMappingError:Error {case unsupported,metadataUnavailable,cancelled}
public struct StartupDataProof:Equatable,Sendable {
    public let dataPath:String,containerDevice:String,systemDevice:String
}
/// Pure verifier of public diskutil plist metadata, NOT mount-path guessing.
/// Root is normally an APFS SNAPSHOT: its UUID must match a snapshot belonging
/// to the group's System member, not the System volume UUID itself.
public enum StartupDataMapping {
    public static let dataPath="/System/Volumes/Data"
    public static func verify(root:[String:Any],data:[String:Any],groups:[String:Any],snapshots:[String:Any])throws->StartupDataProof {
        guard root["FilesystemType"] as? String == "apfs",root["MountPoint"] as? String == "/",
              root["APFSSnapshot"] as? Bool == true,
              let snapshot=root["APFSSnapshotUUID"] as? String,!snapshot.isEmpty,
              let group=root["APFSVolumeGroupID"] as? String,!group.isEmpty,
              let container=root["APFSContainerReference"] as? String,validDevice(container),
              data["FilesystemType"] as? String == "apfs",data["MountPoint"] as? String == dataPath,
              data["APFSVolumeGroupID"] as? String == group,
              data["APFSContainerReference"] as? String == container,
              let containers=groups["Containers"] as? [[String:Any]] else{throw StartupMappingError.unsupported}
        let matching=containers.filter{$0["ContainerReference"] as? String == container}.flatMap{$0["VolumeGroups"] as? [[String:Any]] ?? []}.filter{$0["APFSVolumeGroupUUID"] as? String == group}
        guard matching.count==1,let volumes=matching[0]["Volumes"] as? [[String:Any]] else{throw StartupMappingError.unsupported}
        let systems=volumes.filter{$0["Role"] as? String == "System"},datas=volumes.filter{$0["Role"] as? String == "Data"}
        guard systems.count==1,datas.count==1,
              let system=systems[0]["DeviceIdentifier"] as? String,validDevice(system),
              let dataDevice=datas[0]["DeviceIdentifier"] as? String,validDevice(dataDevice),system != dataDevice,
              data["DeviceIdentifier"] as? String == dataDevice,
              let dataUUID=datas[0]["DiskUUID"] as? String,!dataUUID.isEmpty,
              data["VolumeUUID"] as? String == dataUUID,
              let snaps=snapshots["Snapshots"] as? [[String:Any]],
              snaps.contains(where:{$0["SnapshotUUID"] as? String == snapshot}) else{throw StartupMappingError.unsupported}
        return StartupDataProof(dataPath:dataPath,containerDevice:container,systemDevice:system)
    }
    public static func systemMember(root:[String:Any],groups:[String:Any])throws->String {
        guard let container=root["APFSContainerReference"] as? String,validDevice(container),let group=root["APFSVolumeGroupID"] as? String,!group.isEmpty,
              let containers=groups["Containers"] as? [[String:Any]] else{throw StartupMappingError.unsupported}
        let members=containers.filter{$0["ContainerReference"] as? String == container}.flatMap{$0["VolumeGroups"] as? [[String:Any]] ?? []}.filter{$0["APFSVolumeGroupUUID"] as? String == group}.flatMap{$0["Volumes"] as? [[String:Any]] ?? []}.filter{$0["Role"] as? String == "System"}
        guard members.count==1,let device=members[0]["DeviceIdentifier"] as? String,validDevice(device) else{throw StartupMappingError.unsupported};return device
    }
    public static func validDevice(_ s:String)->Bool {s.range(of:"^disk[0-9]+(s[0-9]+)*$",options:.regularExpression) != nil}
}
/// Consent is in-memory. Returning is merely a one-attempt trigger, NEVER proof
/// of FDA; neither construction nor first activation creates an attempt.
public struct StartupConsent:Equatable,Sendable {
    public private(set) var armed=false,sawResign=false,attempts=0
    public init(){}
    public mutating func request(){armed=true;sawResign=false}
    public mutating func resigned(){if armed{sawResign=true}}
    public mutating func returned()->Bool {guard armed,sawResign else{return false};return take()}
    public mutating func manualContinue()->Bool {guard armed else{return false};return take()}
    private mutating func take()->Bool {armed=false;sawResign=false;attempts+=1;return true}
    public mutating func cancel(){armed=false;sawResign=false}
}
