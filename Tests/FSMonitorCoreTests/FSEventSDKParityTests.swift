#if os(macOS)
import CoreServices
import XCTest
@testable import FSMonitorCore

final class FSEventSDKParityTests: XCTestCase {
    func testDecoderRawValuesMatchPublicSDK() {
        XCTAssertEqual(FSEventFlag.mustScanSubDirs.rawValue, UInt32(kFSEventStreamEventFlagMustScanSubDirs))
        XCTAssertEqual(FSEventFlag.itemCreated.rawValue, UInt32(kFSEventStreamEventFlagItemCreated))
        XCTAssertEqual(FSEventFlag.itemRemoved.rawValue, UInt32(kFSEventStreamEventFlagItemRemoved))
        XCTAssertEqual(FSEventFlag.itemRenamed.rawValue, UInt32(kFSEventStreamEventFlagItemRenamed))
        XCTAssertEqual(FSEventFlag.itemModified.rawValue, UInt32(kFSEventStreamEventFlagItemModified))
        XCTAssertEqual(FSEventFlag.itemIsFile.rawValue, UInt32(kFSEventStreamEventFlagItemIsFile))
        XCTAssertEqual(FSEventFlag.itemIsDir.rawValue, UInt32(kFSEventStreamEventFlagItemIsDir))
        XCTAssertEqual(FSEventFlag.itemIsSymlink.rawValue, UInt32(kFSEventStreamEventFlagItemIsSymlink))
        XCTAssertEqual(FSEventFlag.itemCloned.rawValue, UInt32(kFSEventStreamEventFlagItemCloned))
        XCTAssertFalse(FSEventFlagDecoder.includesProcessIdentifier)
    }
}
#endif
