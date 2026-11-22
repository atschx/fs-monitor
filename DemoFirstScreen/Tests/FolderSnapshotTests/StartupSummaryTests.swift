import XCTest
import Foundation
import DemoFirstScreenCore
import FolderSnapshotAdapter
import ReadOnlyScanner

final class StartupSummaryTests:XCTestCase {
    func metadata()->([String:Any],[String:Any],[String:Any],[String:Any]) {
        let root:[String:Any]=["FilesystemType":"apfs","MountPoint":"/","APFSSnapshot":true,"APFSSnapshotUUID":"BOOT-SNAPSHOT","APFSVolumeGroupID":"GROUP","APFSContainerReference":"disk9","VolumeUUID":"NOT-SYSTEM-VOLUME-UUID"]
        let data:[String:Any]=["FilesystemType":"apfs","MountPoint":"/System/Volumes/Data","APFSVolumeGroupID":"GROUP","APFSContainerReference":"disk9","DeviceIdentifier":"disk9s2","VolumeUUID":"DATA-UUID"]
        let groups:[String:Any]=["Containers":[["ContainerReference":"disk9","VolumeGroups":[["APFSVolumeGroupUUID":"GROUP","Volumes":[["Role":"System","DeviceIdentifier":"disk9s1","DiskUUID":"SYSTEM-UUID"],["Role":"Data","DeviceIdentifier":"disk9s2","DiskUUID":"DATA-UUID"]]]]]]]
        return(root,data,groups,["Snapshots":[["SnapshotUUID":"BOOT-SNAPSHOT"]]])
    }
    func testActualSnapshotIdentityNotConfusedWithVolumeUUID()throws{let(r,d,g,s)=metadata();let p=try StartupDataMapping.verify(root:r,data:d,groups:g,snapshots:s);XCTAssertEqual(p.dataPath,StartupDataMapping.dataPath);XCTAssertEqual(p.systemDevice,"disk9s1")}
    func testExistingPathWithoutRoleEvidenceRejected(){let(r,d,_,s)=metadata();XCTAssertThrowsError(try StartupDataMapping.verify(root:r,data:d,groups:[:],snapshots:s))}
    func testWrongDataUUIDRejected(){let(r,dd,g,s)=metadata();var d=dd;d["VolumeUUID"]="OTHER";XCTAssertThrowsError(try StartupDataMapping.verify(root:r,data:d,groups:g,snapshots:s))}
    func testBootSnapshotMustBelongToSystemMember(){let(r,d,g,_)=metadata();XCTAssertThrowsError(try StartupDataMapping.verify(root:r,data:d,groups:g,snapshots:["Snapshots":[["SnapshotUUID":"OTHER"]]]))}
    func testWrongGroupOrContainerRejected(){let(r,dd,g,s)=metadata();for key in ["APFSVolumeGroupID","APFSContainerReference"]{var d=dd;d[key]="OTHER";XCTAssertThrowsError(try StartupDataMapping.verify(root:r,data:d,groups:g,snapshots:s))}}
    func testNonAPFSNeverFallsBackHomeOrRoot(){let(rr,d,g,s)=metadata();var r=rr;r["FilesystemType"]="hfs";XCTAssertThrowsError(try StartupDataMapping.verify(root:r,data:d,groups:g,snapshots:s));XCTAssertFalse(StartupDataMapping.validDevice("disk9;foo"))}
    func testFirstActivationNeverStartsAnything(){var c=StartupConsent();XCTAssertFalse(c.returned());XCTAssertFalse(c.manualContinue());XCTAssertEqual(c.attempts,0)}
    func testReturnIsOneAttemptNotFDAProof(){var c=StartupConsent();c.request();XCTAssertFalse(c.returned());c.resigned();XCTAssertTrue(c.returned());XCTAssertFalse(c.returned());XCTAssertFalse(c.manualContinue());XCTAssertEqual(c.attempts,1)}
    func testCancellingAuthorizationPreventsLaterReturn(){var c=StartupConsent();c.request();c.resigned();c.cancel();XCTAssertFalse(c.returned());c.request();XCTAssertTrue(c.manualContinue());c.resigned();XCTAssertFalse(c.returned())}
    func testTinyAdjacentMeasuredCardsDoNotOverlap(){let cs=(0..<5).map{MeasuredCard(id:"\($0)",anchor:Point2D(x:1950+Double($0)*4,y:1500),width:480,height:180)};let boxes=CardAvoidance.layout(cs);XCTAssertEqual(boxes.count,5);let values=Array(boxes.values);for i in values.indices{XCTAssertGreaterThanOrEqual(values[i].minX,28);XCTAssertLessThanOrEqual(values[i].maxX,2372);for j in values.indices where j>i{XCTAssertFalse(values[i].overlaps(values[j]))}}}
    func testLargeMeasuredCardsPackAndLeadWithoutGeometryChanges(){let cs=(0..<5).map{MeasuredCard(id:"\($0)",anchor:Point2D(x:1200,y:1700),width:600,height:400)};let boxes=Array(CardAvoidance.layout(cs).values);XCTAssertEqual(boxes.count,5);XCTAssertTrue(boxes.contains{$0.needsLeader});for i in boxes.indices{XCTAssertGreaterThanOrEqual(boxes[i].minY,800);XCTAssertLessThanOrEqual(boxes[i].maxY,1715);for j in boxes.indices where j>i{XCTAssertFalse(boxes[i].overlaps(boxes[j]))}}}
    func testCandidateBucketRulesSameAsCompleteWithoutClaimingChart(){let items=FolderAdapter.candidateItems(["A":1,"B":2,"C":3,"D":4,"E":5,".":10]);XCTAssertEqual(items.count,5);XCTAssertEqual(items.last?.bytes,11);XCTAssertTrue(items.allSatisfy{$0.readStatus == .partial})}
    func testActualOwnFixtureCandidateInodesNotDoubleCounted()throws {
        let parent=ProcessInfo.processInfo.environment["FS_TEST_FIXTURE_PARENT"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.temporaryDirectory.appendingPathComponent("FSMonitor-OwnFixtures")
        let root=parent.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root.appendingPathComponent("A"),withIntermediateDirectories:true)
        let file=root.appendingPathComponent("z");try Data(repeating:1,count:21).write(to:file);try FileManager.default.linkItem(at:file,to:root.appendingPathComponent("A/link"))
        var last=ScanCandidates(visited:0,logicalByTop:[:]);let result=DirectoryScanner.scan(root:root,cancellation:ScanCancellation(),progressStride:1,candidates:{last=$0})
        XCTAssertTrue(result.completed);XCTAssertEqual(last.logicalByTop.values.reduce(0,+),21);XCTAssertEqual(last.logicalByTop["A"],21);XCTAssertEqual(last.logicalByTop["."] ?? 0,0)
    }
}
